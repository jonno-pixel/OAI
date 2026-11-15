# JJS Vrij 2.0

Een nieuw zelfstandig Swift/SwiftUI-project voor lokale GGUF-gesprekken, geschreven voor de eisen in deze opdracht. Het Xcode-project compileert uitsluitend de acht Swift-bestanden in deze map onder `Sources/`. Geen van de appbronbestanden uit `jjs-original/` wordt gebruikt. Het projectbestand wordt onafhankelijk gegenereerd met `scripts/make_project.py`.

## Wat nieuw is geschreven

- `Domain.swift`: gespreksgegevens, werkopdrachten, tekstcodering en streaming van UTF-8.
- `LibraryVault.swift`: atomaire JSON-opslag met revisiecontrole en JSON-/tekstexport.
- `ModelFiles.swift`: GGUF-import, bytecontrole, modelgroepen, URL-downloads en export.
- `GGUFRunner.swift`: eigendom van native modelcontexten, tokenisering, modeltemplate/directe invoer, contextverschuivingen en streaming van antwoorden.
- `Workspace.swift`: duurzame wachtrij, gesprekken, instellingen en lifecycle-coördinatie.
- `MediaReader.swift`: lokale tekst-, PDF-, OCR- en audio-invoer via Apple-frameworks.
- `Screens.swift`: nieuwe tabstructuur met Gesprek, Bibliotheek, Modellen en Instellingen.
- `JJSVrijApp.swift`: nieuwe SwiftUI-appstart.

Het nieuwe icoon is een afzonderlijk gegenereerd JJS-ontwerp, als ondoorzichtige 1024×1024-pixelafbeelding opgenomen. iOS verzorgt de afgeronde hoeken.

## Vooraf gecompileerde afhankelijkheid

`Frameworks/llama.xcframework` is de bestaande, door de gebruiker aangeleverde native iOS-arm64-bibliotheek. Die bibliotheek is niet vanaf nul herschreven. Zij leest GGUF-modelgegevens en voert de inferentieberekeningen uit. De licentie staat in `LLAMA-LICENSE.txt` en is in de app gebundeld. De app gebruikt verder standaard Apple-frameworks. Er is geen webview-app, JavaScript-runtime, Python-runtime of te downloaden uitvoerbare appcode.

Een volledig nieuw geschreven GGUF-rekenbibliotheek is hiermee **niet** geleverd. Deze afhankelijkheid is expliciet vermeld zodat de eigen nieuwe appcode en de meegeleverde bibliotheek afzonderlijk controleerbaar zijn.

## Gedrag

De app voegt geen inhoudsfilter, systeemprompt, verborgen vervolgopdracht, chatquotum, maximumaantal antwoordtokens of generatietimer toe. Tokens zijn normale modelinvoer en -uitvoer. Antwoorden stoppen bij een eindtoken, de stopknop, een uitvoeringsfout of onderbreking door iOS. De context is eindig; contextverschuivingen bewaren een deel van de actieve modelcontext terwijl alle opgeslagen berichten behouden blijven. De verwerkingsbatch is een werkbuffer, geen antwoordlengtelimiet.

Een GGUF-bestand moet uitvoerbaar zijn met de meegeleverde bibliotheek en binnen de mogelijkheden van het toestel. Deze tekstgeneratie-app garandeert geen ondersteuning voor iedere GGUF-architectuur, afbeeldingsgenerator of encoder. CPU, GPU, RAM, opslag, thermische regeling en iOS-uitvoering zijn niet onbeperkt.

## Bestanden

- Importeer gewone UTF-8- of UTF-16-tekst als volledige inhoud van een nieuw gesprek.
- Exporteer één gesprek of alle gesprekken als leesbare `.txt`.
- Gebruik `.json` voor overdracht van berichtrollen, inhoud en statussen. Geïmporteerde wachtende/actieve antwoorden worden gestopt, niet onverwacht opnieuw gegenereerd.
- Importeer GGUF-bestanden of een map. Bij gesplitste modellen moeten alle delen samen worden geselecteerd.
- Download via rechtstreekse HTTP(S)-bestandslinks. Voor gesplitste bestanden één URL per regel. GGUF-headers en kopiehashes worden gecontroleerd; mislukte overdrachten worden niet in de modellenlijst geplaatst.
- Deel/exporteer een model via het native iOS-deelvenster, inclusief alle bijbehorende modeldelen.
- Bijlagen: tekst, PDF-tekst/OCR, afbeeldingen als OCR-tekst en audio via lokale Apple-spraakherkenning indien beschikbaar.

Modelbestanden worden niet aangepast. De gewone-tekstweergave toont de ontvangen antwoordtekst letterlijk, ook code en leestekens.

## Bouwen en controleren

Open `JJSVrij.xcodeproj` met Xcode op een Mac. Het framework ondersteunt echte iPhones/iPads, niet de simulator. Bundle-ID: `nl.jjs.vrij`; versie: `2.0`.

```bash
python3 scripts/verify.py
bash scripts/build.sh CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

De verificatie test tekstcoderingen, Unicode, lange tekst, atomaire opslag, revisievolgorde, herstel van onderbroken antwoorden, JSON-overdracht, GGUF-bestandsoverdracht, gesplitste modellen en afgewezen downloads. GGUF-overdrachtstests gebruiken herkenbare bestandsfixtures en zijn geen inferentietest met een echt model.

De GitHub-build compileert het zelfstandige project met een iOS 26 SDK of nieuwer en controleert het ARM64-bestand, de resources en de IPA. Er is geen echt iOS-toestel beschikbaar in deze omgeving. App Store-toelating of foutloze werking is niet aangetoond. Voor distributie zijn Apple-ondertekening, provisioning, App Store Connect-metadata, privacybeleid-/support-URLs, screenshots, toesteltests en beoordeling door Apple nodig. De geleverde IPA is ongetekend.
