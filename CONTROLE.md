# Validatie en testplan

## In deze Linux-omgeving

- Swift-bestanden syntactisch geparseerd met Tree-sitter (zie VALIDATIE.txt).
- Xcode-projectstructuur en bestandsverwijzingen met een OpenStep-parser gecontroleerd.
- Info.plist en gedeelde Xcode-scheme geparseerd.
- Bash-buildscript gecontroleerd met bash -n.
- SDK-voorwaarde en unsigned-IPA-pakketopbouw statisch nagekeken.

Syntaxiscontrole vervangt geen Swift-typecontrole of Xcode-build. Er is hier
geen Swift-compiler, Xcode, Apple SDK of iPhone beschikbaar. De native interface
is niet als screenshot of simulatorpreview gecontroleerd.

## Uit te voeren op de cloud-Mac / iPhone

1. Bouw het project met de passende SDK. Los eventuele compiler- of
   signingmeldingen op voordat je de app als werkend beschouwt.
2. Installeer via AltStore. Controleer icoon/starten en vernieuwen van signing.
3. Test OpenAI: correcte sleutel/model, streaming, foutieve sleutel, lege
   modellenkeuze, ongeschikt model en eventueel onvoldoende API-tegoed.
4. Test Ollama en LM Studio ieder afzonderlijk met een daadwerkelijk geladen
   model, pc op LAN en iPhone-netwerktoestemming. Test ook pc uit/server uit.
5. Stop een lange stream; controleer dat de UI weer bedienbaar wordt en dat
   het incomplete antwoord als onderbroken bewaard blijft.
6. Wissel dienst en terug: controleer URL/model/sleutel per dienst. Annuleer
   wijzigingen en controleer dat de oude instellingen blijven staan.
7. Start meerdere gesprekken, sluit de app volledig en heropen. Controleer
   geschiedenis, titels, verwijderen, grote tekst, donker/licht en rotatie.
8. Test wifi-uitval, app naar achtergrond en terug, ongeldige URL, timeout
   en HTTP-fouten. Controleer dat er geen automatische dubbele verzending is.
9. Verwijder een API-sleutel via het instellingenveld en bewaar. Controleer
   dat OpenAI vervolgens opnieuw om een sleutel vraagt.
