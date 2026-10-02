#include "AraVFVoicePack.h"
#include "Misc/Crc.h"

int32 UAraVFVoicePack::GetOptionValue() const
{
	const FString Code = LanguageCode.ToLower();
	if (Code == TEXT("fr"))
	{
		return 0;   // valeur du francais depuis la version 1.0 (reglage deja enregistre chez les joueurs)
	}
	// stable d'une version a l'autre, positive, jamais 0 ni 1 (francais, anglais d'origine)
	return 1000 + int32(FCrc::StrCrc32(*Code) % 1000000u);
}
