#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Misc/Variant.h"
#include "Containers/Ticker.h"
#include "FGOptionInterface.h"
#include "AraVFSubsystem.generated.h"

class UFGMessage;
class UFGUserSetting;
class UAkAudioEvent;
class UAraVFVoicePack;

/**
 * Donne a l'IA FICSIT la voix d'un pack de langue, selon l'option Options > Audio > Langue de l'IA FICSIT.
 *
 * Les packs sont trouves au demarrage : chaque mod (AraVF compris, pour le francais) peut contenir un asset
 * UAraVFVoicePack nomme AraVFVoicePack a la racine de son contenu. Chaque pack ajoute sa langue a l'option.
 * Cree automatiquement par le moteur avec la GameInstance.
 */
UCLASS()
class ARAVF_API UAraVFSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	/** Identifiant du reglage (asset US_AraVF_VoiceLanguage) */
	static const TCHAR* VoiceLanguageOption;
	/** Valeur de l'option pour l'anglais d'origine, et valeur par defaut du reglage (francais) */
	static constexpr int32 OriginalLanguage = 1;
	static constexpr int32 DefaultLanguage = 0;

	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

private:
	/** Cherche les packs dans les mods installes, prepare leurs messages et cinematiques, remplit l'option. */
	void DiscoverPacks();
	void LoadPack(UAraVFVoicePack* Pack);
	/** Liste de l'option : chaque pack (par nom), puis English. */
	void FillLanguageChoices();
	/** Lit l'option et applique la langue correspondante (sans effet si deja appliquee). */
	void ApplyVoiceLanguage();
	/** Remet chaque message et chaque evenement d'outro dans son etat d'origine. */
	void RestoreOriginals();
	/** Arrete la voix d'une cinematique en cours et remet les sons du jeu a niveau. */
	void StopTrigger(int32 Index);
	void OnVoiceLanguageChanged(FString StrId, FVariant Value);
	void OnPostWorldInitialization(UWorld* World, const UWorld::InitializationValues IVS);
	IFGOptionInterface* GetOptions() const;
	/** Pose le libelle et l'infobulle de l'option dans la langue du jeu (table AraVFSettingTexts.inl). */
	void LocalizeSetting();
	bool TickTriggers(float DeltaTime);

	/** Asset de l'option : le referencer garde les libelles et la liste de langues poses ici. */
	UPROPERTY()
	TObjectPtr<UFGUserSetting> LanguageSetting;
	FDelegateHandle CultureChangedHandle;

	/** Packs trouves, et leur valeur dans l'option */
	UPROPERTY()
	TArray<TObjectPtr<UAraVFVoicePack>> Packs;
	TArray<int32> PackValues;

	/** Messages doubles par au moins un pack. Les referencer empeche leur dechargement (qui annulerait le remplacement). */
	UPROPERTY()
	TArray<TObjectPtr<UFGMessage>> Messages;
	TMap<FString, int32> MessageIndex;
	/** Evenement et horaires d'origine de chaque message (pour l'anglais) */
	TArray<TSoftObjectPtr<UAkAudioEvent>> OriginalEvents;
	TArray<TArray<float>> OriginalTimeStamps;
	/** Pour chaque pack, chaque entree de Messages : index dans Messages, ou INDEX_NONE si inutilisable */
	TArray<TArray<int32>> PackMessages;

	/** Outro : evenements du jeu dont l'identifiant Wwise est remplace par celui de la voix du pack */
	UPROPERTY()
	TArray<TObjectPtr<UAkAudioEvent>> SwapGameEvents;
	TArray<int32> SwapOriginalIds;
	TMap<FString, int32> SwapIndex;
	struct FPackSwap { int32 Swap; int32 EventId; };
	TArray<TArray<FPackSwap>> PackSwaps;
	/** Voix d'outro des packs, chargees des le demarrage (banques pretes quand la cinematique les demande) */
	UPROPERTY()
	TArray<TObjectPtr<UAkAudioEvent>> SwapVoiceEvents;

	/** Intro : voix du pack jouee en plus d'un evenement du jeu, des qu'il demarre */
	struct FTrigger
	{
		int32 Pack;
		uint32 GameId;
		uint32 PlayingId;
		/** L'evenement du jeu jouait au tick precedent : la voix ne demarre qu'avec lui (pas en cours de route) */
		bool bWasGamePlaying;
	};
	TArray<FTrigger> Triggers;
	UPROPERTY()
	TArray<TObjectPtr<UAkAudioEvent>> TriggerEvents;
	UPROPERTY()
	TArray<TObjectPtr<UAkAudioEvent>> TriggerResetEvents;
	FTSTicker::FDelegateHandle TriggerTicker;

	/** Pack applique (index dans Packs), INDEX_NONE = anglais d'origine */
	static constexpr int32 NotAppliedYet = -2;
	int32 AppliedPack = NotAppliedYet;
	FOnOptionUpdated OptionUpdatedDelegate;
	bool bSubscribed = false;
	FDelegateHandle WorldInitHandle;
};
