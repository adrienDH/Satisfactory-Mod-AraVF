#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "AraVFVoicePack.generated.h"

/**
 * Pack de langue pour la voix de l'IA FICSIT.
 *
 * Un pack est un mod (contenu seulement, sans code) qui depend d'AraVF et contient, a la racine de son
 * contenu, un asset de cette classe nomme AraVFVoicePack : /<NomDuMod>/AraVFVoicePack. AraVF le trouve
 * au demarrage et ajoute sa langue a l'option Options > Audio > Langue de l'IA FICSIT.
 *
 * Les chemins sont des chaines (et non des references d'assets) : les assets du jeu ne doivent pas etre
 * suivis a l'empaquetage du mod.
 */

/** Un message de l'IA double : asset du jeu, evenement de la voix, horaire de chaque sous-titre. */
USTRUCT(BlueprintType)
struct ARAVF_API FAraVFMessageVoice
{
	GENERATED_BODY()

	/** Message du jeu (FGMessage), ex. /Game/FactoryGame/Narrative/Tier1/MSG_Tier1_Schematic_1-1.MSG_Tier1_Schematic_1-1 */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString Message;

	/** Evenement Wwise (AkAudioEvent) du pack qui joue la voix, ex. /AraVF_ES/Audio/Play_X.Play_X */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString Event;

	/** Debut de chaque sous-titre dans la voix (s), autant que de sous-titres du message */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	TArray<float> TimeStamps;
};

/** Voix de cinematique remplacee : l'evenement du jeu joue celui du pack. */
USTRUCT(BlueprintType)
struct ARAVF_API FAraVFCinematicSwap
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString GameEvent;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString Event;
};

/** Voix de cinematique jouee en plus d'un evenement du jeu, des qu'il demarre (intro). */
USTRUCT(BlueprintType)
struct ARAVF_API FAraVFCinematicTrigger
{
	GENERATED_BODY()

	/** Nom Wwise de l'evenement du jeu, ex. Play_Cinematic_DropPod */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString GameEventName;

	/** Evenement du pack joue au demarrage */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString Event;

	/** Evenement du pack joue a la fin (remise a niveau des sons du jeu), facultatif */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString ResetEvent;
};

UCLASS(BlueprintType)
class ARAVF_API UAraVFVoicePack : public UDataAsset
{
	GENERATED_BODY()

public:
	/** Code de la langue, ex. fr, es */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FString LanguageCode;

	/** Nom de la langue dans l'option, dans cette langue : Français, Español... */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	FText LanguageName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	TArray<FAraVFMessageVoice> Messages;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	TArray<FAraVFCinematicSwap> CinematicSwaps;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AraVF")
	TArray<FAraVFCinematicTrigger> CinematicTriggers;

	/** Valeur de l'option pour cette langue : stable, deduite du code (0 = francais, 1 = anglais d'origine). */
	int32 GetOptionValue() const;
};
