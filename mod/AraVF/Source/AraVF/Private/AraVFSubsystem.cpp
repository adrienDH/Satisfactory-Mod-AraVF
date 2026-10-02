#include "AraVFSubsystem.h"
#include "AraVF.h"
#include "AraVFVoicePack.h"
#include "AkAudioDevice.h"
#include "AkAudioEvent.h"
#include "FGGameUserSettings.h"
#include "Narrative/FGMessage.h"
#include "Settings/FGUserSetting.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/PackageName.h"
#include "Internationalization/Culture.h"
#include "Internationalization/Internationalization.h"

namespace
{
	struct FAraVFSettingText
	{
		const TCHAR* Culture;
		const TCHAR* Name;
		const TCHAR* ToolTip;
	};

	// GSettingTexts : libelles de l'option par langue du jeu
	#include "AraVFSettingTexts.inl"

	const TCHAR* LanguageSettingPath = TEXT("/AraVF/Settings/US_AraVF_VoiceLanguage.US_AraVF_VoiceLanguage");
	/** Nom de l'asset du pack a la racine du contenu de chaque mod */
	const TCHAR* PackAssetName = TEXT("AraVFVoicePack");
	/** Identifiant de lecture d'une voix de cinematique qui n'a pas pu demarrer (ne pas reessayer) */
	constexpr uint32 FailedPlayingId = MAX_uint32;
	/** Horaire maximal accepte pour un sous-titre (s) : au-dela, valeur aberrante d'un pack */
	constexpr float MaxTimeStamp = 600.f;

	// FAkAudioDevice::IsEventIDActive est privee : acces par instanciation explicite de modele,
	// le seul moyen standard de lire un membre prive (le suivi des evenements joues est celui du plugin).
	// Verifie avec l'integration Wwise 2025.1.6 du jeu ; une signature differente ne compilerait plus.
	template <typename Tag, typename Tag::Type Member>
	struct TAraVFPrivateAccess
	{
		friend typename Tag::Type AraVFGetPrivate(Tag) { return Member; }
	};
	struct FIsEventIDActiveTag
	{
		using Type = bool (FAkAudioDevice::*)(uint32);
		friend Type AraVFGetPrivate(FIsEventIDActiveTag);
	};
	template struct TAraVFPrivateAccess<FIsEventIDActiveTag, &FAkAudioDevice::IsEventIDActive>;

	/** Charge un objet par son chemin ("/Mod/Dossier/Nom.Nom"), sans erreur du moteur si le chemin est vide ou absent. */
	template <typename T>
	T* LoadChecked(const FString& Path)
	{
		if (Path.IsEmpty() || !FPackageName::DoesPackageExist(FPackageName::ObjectPathToPackageName(Path)))
		{
			return nullptr;
		}
		return LoadObject<T>(nullptr, *Path, nullptr, LOAD_NoWarn | LOAD_Quiet);
	}

	float SanitizeTimeStamp(float Value)
	{
		return FMath::IsFinite(Value) ? FMath::Clamp(Value, 0.f, MaxTimeStamp) : 0.f;
	}
}

const TCHAR* UAraVFSubsystem::VoiceLanguageOption = TEXT("AraVF.VoiceLanguage");

void UAraVFSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

#if WITH_EDITOR
	// Dans l'editeur, les messages sont les copies de substitution du projet :
	// les modifier en memoire risquerait de les ecraser a la prochaine sauvegarde.
	if (GIsEditor)
	{
		return;
	}
#endif

	LanguageSetting = LoadObject<UFGUserSetting>(nullptr, LanguageSettingPath);
	if (!LanguageSetting)
	{
		UE_LOG(LogAraVF, Warning, TEXT("Option introuvable : %s"), LanguageSettingPath);
	}
	LocalizeSetting();
	CultureChangedHandle = FInternationalization::Get().OnCultureChanged().AddUObject(this, &UAraVFSubsystem::LocalizeSetting);

	DiscoverPacks();
	OptionUpdatedDelegate = FOnOptionUpdated::CreateUObject(this, &UAraVFSubsystem::OnVoiceLanguageChanged);
	ApplyVoiceLanguage();
	// Le reglage est enregistre par la Game Feature du mod, parfois apres ce sous-systeme :
	// on relit l'option a chaque nouveau monde (menu, partie) tant qu'on n'y est pas abonne.
	if (!bSubscribed)
	{
		WorldInitHandle = FWorldDelegates::OnPostWorldInitialization.AddUObject(this, &UAraVFSubsystem::OnPostWorldInitialization);
	}
}

void UAraVFSubsystem::Deinitialize()
{
	FTSTicker::GetCoreTicker().RemoveTicker(TriggerTicker);
	FWorldDelegates::OnPostWorldInitialization.Remove(WorldInitHandle);
	FInternationalization::Get().OnCultureChanged().Remove(CultureChangedHandle);
	if (bSubscribed)
	{
		if (IFGOptionInterface* Options = GetOptions())
		{
			Options->UnsubscribeToOptionUpdate(VoiceLanguageOption, OptionUpdatedDelegate);
		}
	}
	RestoreOriginals();
	Super::Deinitialize();
}

void UAraVFSubsystem::DiscoverPacks()
{
	for (const TSharedRef<IPlugin>& Plugin : IPluginManager::Get().GetEnabledPluginsWithContent())
	{
		const FString Package = FString::Printf(TEXT("/%s/%s"), *Plugin->GetName(), PackAssetName);
		UAraVFVoicePack* Pack = LoadChecked<UAraVFVoicePack>(Package + TEXT(".") + PackAssetName);
		if (!Pack)
		{
			continue;
		}
		if (Pack->LanguageCode.TrimStartAndEnd().IsEmpty())
		{
			UE_LOG(LogAraVF, Warning, TEXT("%s : pack sans code de langue, ignore"), *Package);
			continue;
		}
		if (PackValues.Contains(Pack->GetOptionValue()))
		{
			UE_LOG(LogAraVF, Warning, TEXT("%s : langue %s deja fournie par un autre pack, ignore"), *Package, *Pack->LanguageCode);
			continue;
		}
		LoadPack(Pack);
		const int32 Usable = PackMessages.Last().FilterByPredicate([](int32 I) { return I != INDEX_NONE; }).Num();
		UE_LOG(LogAraVF, Display, TEXT("Pack %s (mod %s) : %d message(s) utilisable(s) sur %d, %d voix de cinematique"),
			*Pack->LanguageCode, *Plugin->GetName(), Usable, Pack->Messages.Num(), PackSwaps.Last().Num() + Pack->CinematicTriggers.Num());
		if (Usable < Pack->Messages.Num())
		{
			UE_LOG(LogAraVF, Warning, TEXT("Pack %s : %d message(s) ignore(s), voix d'origine pour ceux-la (detail : -LogCmds=\"LogAraVF Verbose\")"),
				*Pack->LanguageCode, Pack->Messages.Num() - Usable);
		}
	}
	if (Triggers.Num() && !TriggerTicker.IsValid())
	{
		TriggerTicker = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateUObject(this, &UAraVFSubsystem::TickTriggers), 0.05f);
	}
	FillLanguageChoices();
}

void UAraVFSubsystem::LoadPack(UAraVFVoicePack* Pack)
{
	const int32 PackId = Packs.Add(Pack);
	PackValues.Add(Pack->GetOptionValue());
	const FString& Code = Pack->LanguageCode;

	// Messages : un message est memorise (evenement et horaires d'origine) la premiere fois qu'un pack le double
	TArray<int32>& Entries = PackMessages.AddDefaulted_GetRef();
	for (const FAraVFMessageVoice& Voice : Pack->Messages)
	{
		int32 Index = INDEX_NONE;
		if (const int32* Known = MessageIndex.Find(Voice.Message))
		{
			Index = *Known;
		}
		else
		{
			if (UFGMessage* Message = LoadChecked<UFGMessage>(Voice.Message))
			{
				Index = Messages.Add(Message);
				OriginalEvents.Add(Message->mAudioEvent);
				TArray<float>& Stamps = OriginalTimeStamps.AddDefaulted_GetRef();
				for (const auto& Subtitle : Message->mSubtitles)
				{
					Stamps.Add(Subtitle.TimeStamp);
				}
			}
			else
			{
				UE_LOG(LogAraVF, Verbose, TEXT("[%s] message introuvable : %s"), *Code, *Voice.Message);
			}
			MessageIndex.Add(Voice.Message, Index);
		}
		if (Index != INDEX_NONE && Messages[Index]->mSubtitles.Num() != Voice.TimeStamps.Num())
		{
			// Les horaires seraient decales : ce pack garde la voix d'origine pour ce message.
			UE_LOG(LogAraVF, Verbose, TEXT("[%s] %s : %d sous-titres dans le jeu, %d dans le pack"),
				*Code, *Messages[Index]->GetName(), Messages[Index]->mSubtitles.Num(), Voice.TimeStamps.Num());
			Index = INDEX_NONE;
		}
		if (Index != INDEX_NONE && !FPackageName::DoesPackageExist(FPackageName::ObjectPathToPackageName(Voice.Event)))
		{
			UE_LOG(LogAraVF, Verbose, TEXT("[%s] voix introuvable : %s"), *Code, *Voice.Event);
			Index = INDEX_NONE;
		}
		Entries.Add(Index);
	}

	// Outro : evenements du jeu et du pack charges des maintenant et gardes en memoire
	TArray<FPackSwap>& Swaps = PackSwaps.AddDefaulted_GetRef();
	for (const FAraVFCinematicSwap& Swap : Pack->CinematicSwaps)
	{
		UAkAudioEvent* Voice = LoadChecked<UAkAudioEvent>(Swap.Event);
		int32 Index = INDEX_NONE;
		if (const int32* Known = SwapIndex.Find(Swap.GameEvent))
		{
			Index = *Known;
		}
		else
		{
			if (UAkAudioEvent* Game = LoadChecked<UAkAudioEvent>(Swap.GameEvent))
			{
				Index = SwapGameEvents.Add(Game);
				SwapOriginalIds.Add(Game->EventCookedData.EventId);
			}
			SwapIndex.Add(Swap.GameEvent, Index);
		}
		if (Index == INDEX_NONE || !Voice)
		{
			UE_LOG(LogAraVF, Warning, TEXT("[%s] voix de cinematique ignoree : %s"), *Code, *Swap.GameEvent);
			continue;
		}
		SwapVoiceEvents.Add(Voice);
		Swaps.Add({Index, Voice->EventCookedData.EventId});
	}

	// Intro : voix jouee quand l'evenement du jeu demarre
	for (const FAraVFCinematicTrigger& Trigger : Pack->CinematicTriggers)
	{
		UAkAudioEvent* Voice = LoadChecked<UAkAudioEvent>(Trigger.Event);
		if (!Voice || Trigger.GameEventName.IsEmpty())
		{
			UE_LOG(LogAraVF, Warning, TEXT("[%s] voix de cinematique introuvable : %s"), *Code, *Trigger.Event);
			continue;
		}
		UAkAudioEvent* Reset = LoadChecked<UAkAudioEvent>(Trigger.ResetEvent);
		if (!Reset && !Trigger.ResetEvent.IsEmpty())
		{
			UE_LOG(LogAraVF, Warning, TEXT("[%s] remise a niveau introuvable : %s"), *Code, *Trigger.ResetEvent);
		}
		Triggers.Add({PackId, FAkAudioDevice::GetShortIDFromString(Trigger.GameEventName), AK_INVALID_PLAYING_ID, false});
		TriggerEvents.Add(Voice);
		TriggerResetEvents.Add(Reset);
	}
}

void UAraVFSubsystem::FillLanguageChoices()
{
	UFGUserSetting_IntSelector* Selector = LanguageSetting ? Cast<UFGUserSetting_IntSelector>(LanguageSetting->ValueSelector) : nullptr;
	if (!Selector)
	{
		return;
	}
	TArray<int32> Order;
	for (int32 i = 0; i < Packs.Num(); ++i)
	{
		Order.Add(i);
	}
	Order.Sort([this](int32 A, int32 B) { return Packs[A]->LanguageName.CompareTo(Packs[B]->LanguageName) < 0; });

	TArray<FIntegerSelection> Choices;
	for (int32 i : Order)
	{
		FIntegerSelection& Choice = Choices.AddDefaulted_GetRef();
		Choice.Name = Packs[i]->LanguageName.IsEmpty() ? FText::FromString(Packs[i]->LanguageCode) : Packs[i]->LanguageName;
		Choice.Value = PackValues[i];
	}
	FIntegerSelection& English = Choices.AddDefaulted_GetRef();
	English.Name = FText::FromString(TEXT("English"));
	English.Value = OriginalLanguage;
	Selector->IntegerSelectionValues = Choices;
}

IFGOptionInterface* UAraVFSubsystem::GetOptions() const
{
	return UFGGameUserSettings::GetFGGameUserSettings();
}

void UAraVFSubsystem::LocalizeSetting()
{
	if (!LanguageSetting)
	{
		return;
	}
	// nom de culture complet (zh-Hans, pt-BR), puis de moins en moins precis (pt), puis l'anglais
	const FString Culture = FInternationalization::Get().GetCurrentLanguage()->GetName();
	const FAraVFSettingText* Found = nullptr;
	for (FString Candidate = Culture; !Found && !Candidate.IsEmpty(); )
	{
		for (const FAraVFSettingText& Text : GSettingTexts)
		{
			if (Candidate.Equals(Text.Culture, ESearchCase::IgnoreCase))
			{
				Found = &Text;
				break;
			}
		}
		int32 Dash;
		Candidate = Candidate.FindLastChar(TEXT('-'), Dash) ? Candidate.Left(Dash) : FString();
	}
	if (!Found)
	{
		Found = &GSettingTexts[0];   // "en"
	}
	LanguageSetting->DisplayName = FText::FromString(Found->Name);
	LanguageSetting->ToolTip = FText::FromString(Found->ToolTip);
	UE_LOG(LogAraVF, Verbose, TEXT("Libelle de l'option pour la langue %s : %s"), *Culture, Found->Name);
}

void UAraVFSubsystem::OnPostWorldInitialization(UWorld* World, const UWorld::InitializationValues IVS)
{
	ApplyVoiceLanguage();
}

void UAraVFSubsystem::OnVoiceLanguageChanged(FString StrId, FVariant Value)
{
	UE_LOG(LogAraVF, Display, TEXT("Option %s modifiee"), *StrId);
	ApplyVoiceLanguage();
}

void UAraVFSubsystem::RestoreOriginals()
{
	for (int32 i = 0; i < Messages.Num(); ++i)
	{
		Messages[i]->mAudioEvent = OriginalEvents[i];
		const int32 Count = FMath::Min(Messages[i]->mSubtitles.Num(), OriginalTimeStamps[i].Num());
		for (int32 s = 0; s < Count; ++s)
		{
			Messages[i]->mSubtitles[s].TimeStamp = OriginalTimeStamps[i][s];
		}
	}
	for (int32 i = 0; i < SwapGameEvents.Num(); ++i)
	{
		SwapGameEvents[i]->EventCookedData.EventId = SwapOriginalIds[i];
	}
}

void UAraVFSubsystem::ApplyVoiceLanguage()
{
	IFGOptionInterface* Options = GetOptions();
	int32 Value = DefaultLanguage;   // y compris si le reglage n'est pas encore enregistre
	// Le reglage n'existe qu'une fois la Game Feature du mod chargee, apres ce sous-systeme :
	// s'abonner avant ne sert a rien (l'abonnement porte sur une option inconnue), on reessaie donc ici.
	if (Options && UFGGameUserSettings::GetFGGameUserSettings()->FindUserSetting(VoiceLanguageOption))
	{
		if (!bSubscribed)
		{
			Options->SubscribeToOptionUpdate(VoiceLanguageOption, OptionUpdatedDelegate);
			bSubscribed = true;
			FWorldDelegates::OnPostWorldInitialization.Remove(WorldInitHandle);
			UE_LOG(LogAraVF, Display, TEXT("Abonne aux changements de l'option %s"), VoiceLanguageOption);
		}
		const FVariant Option = Options->GetOptionValue(VoiceLanguageOption, FVariant(DefaultLanguage));
		if (Option.GetType() == EVariantTypes::Int32)
		{
			Value = Option.GetValue<int32>();
		}
	}
	// langue d'un pack desinstalle (ou anglais) : voix d'origine
	const int32 PackId = PackValues.IndexOfByKey(Value);
	if (PackId == AppliedPack)
	{
		return;
	}
	if (PackId == INDEX_NONE && Value != OriginalLanguage)
	{
		UE_LOG(LogAraVF, Display, TEXT("Langue %d choisie mais aucun pack installe ne la fournit : voix d'origine"), Value);
	}

	// Une cinematique en cours avec la voix d'un autre pack s'arrete ; elle ne reprend pas en cours de route
	for (int32 t = 0; t < Triggers.Num(); ++t)
	{
		if (Triggers[t].Pack != PackId)
		{
			StopTrigger(t);
		}
	}

	// Messages : chacun revient d'abord a l'origine, puis le pack choisi pose les siens
	RestoreOriginals();
	int32 Applied = 0;
	if (PackId != INDEX_NONE)
	{
		const UAraVFVoicePack* Pack = Packs[PackId];
		for (int32 e = 0; e < Pack->Messages.Num(); ++e)
		{
			const int32 i = PackMessages[PackId][e];
			if (i == INDEX_NONE)
			{
				continue;
			}
			const FAraVFMessageVoice& Voice = Pack->Messages[e];
			// Reference seulement : le jeu charge l'evenement (et sa banque) au moment de jouer le message.
			Messages[i]->mAudioEvent = TSoftObjectPtr<UAkAudioEvent>(FSoftObjectPath(Voice.Event));
			const int32 Count = FMath::Min(Messages[i]->mSubtitles.Num(), Voice.TimeStamps.Num());
			for (int32 s = 0; s < Count; ++s)
			{
				Messages[i]->mSubtitles[s].TimeStamp = SanitizeTimeStamp(Voice.TimeStamps[s]);
			}
			++Applied;
		}
		// Outro : l'evenement du jeu joue la voix du pack (seul son identifiant Wwise change)
		for (const FPackSwap& Swap : PackSwaps[PackId])
		{
			SwapGameEvents[Swap.Swap]->EventCookedData.EventId = Swap.EventId;
		}
	}
	AppliedPack = PackId;
	UE_LOG(LogAraVF, Display, TEXT("Voix de l'IA FICSIT : %s (%d message(s), %d voix de cinematique)"),
		PackId != INDEX_NONE ? *Packs[PackId]->LanguageCode : TEXT("anglais d'origine"), Applied,
		PackId != INDEX_NONE ? PackSwaps[PackId].Num() + Packs[PackId]->CinematicTriggers.Num() : 0);
}

void UAraVFSubsystem::StopTrigger(int32 Index)
{
	FTrigger& Trigger = Triggers[Index];
	if (Trigger.PlayingId == AK_INVALID_PLAYING_ID)
	{
		return;
	}
	if (Trigger.PlayingId != FailedPlayingId)
	{
		if (FAkAudioDevice* Device = FAkAudioDevice::Get())
		{
			Device->StopPlayingID(Trigger.PlayingId, 300);
		}
	}
	if (TriggerResetEvents[Index])
	{
		TriggerResetEvents[Index]->PostOnActor(nullptr, FOnAkPostEventCallback(), 0, false);
	}
	UE_LOG(LogAraVF, Display, TEXT("Cinematique : voix %s arretee"), *TriggerEvents[Index]->GetName());
	Trigger.PlayingId = AK_INVALID_PLAYING_ID;
}

bool UAraVFSubsystem::TickTriggers(float DeltaTime)
{
	FAkAudioDevice* Device = FAkAudioDevice::Get();
	if (!Device)
	{
		return true;
	}
	static const auto IsEventIDActive = AraVFGetPrivate(FIsEventIDActiveTag());
	for (int32 t = 0; t < Triggers.Num(); ++t)
	{
		FTrigger& Trigger = Triggers[t];
		const bool bGamePlaying = (Device->*IsEventIDActive)(Trigger.GameId);
		const bool bStarted = bGamePlaying && !Trigger.bWasGamePlaying;
		Trigger.bWasGamePlaying = bGamePlaying;
		if (bStarted && Trigger.Pack == AppliedPack && Trigger.PlayingId == AK_INVALID_PLAYING_ID)
		{
			// la cinematique demarre : voix du pack par-dessus (elle rend elle-meme muette la voix du jeu)
			Trigger.PlayingId = TriggerEvents[t]->PostOnActor(nullptr, FOnAkPostEventCallback(), 0, false);
			UE_LOG(LogAraVF, Display, TEXT("Cinematique demarree : voix %s (%u)"), *TriggerEvents[t]->GetName(), Trigger.PlayingId);
			if (Trigger.PlayingId == AK_INVALID_PLAYING_ID)
			{
				Trigger.PlayingId = FailedPlayingId;   // echec : ne pas reessayer tant que la cinematique dure
			}
		}
		else if (!bGamePlaying)
		{
			// cinematique terminee ou passee : on coupe la voix du pack et on remet les sons du jeu a niveau
			StopTrigger(t);
		}
	}
	return true;
}
