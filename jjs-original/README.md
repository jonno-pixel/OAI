# JJS Vrij

Een opnieuw opgebouwde SwiftUI-app voor lokale gesprekken met GGUF-modellen. De appcode staat opgesplitst in gewone Swift-bronbestanden; `JJS.xcodeproj` is het enige Xcode-project. De llama.cpp-iOS-engine en het bestaande JJS-appicoon worden als lokale projectresources gebruikt.

## Gedrag

- Geen inhoudsfilter, extra systeemprompt, chatquota, maximumaantal berichten, antwoordtokenlimiet of generatie-time-out.
- Antwoorden lopen door tot het model-eindtoken, een expliciete stop, een enginefout of een onderbreking door iOS.
- Vragen kunnen tijdens een lopend antwoord worden verstuurd en worden duurzaam in volgorde verwerkt.
- Gesprekken worden in SQLite bewaard; import en export gebruiken JSON.
- GGUF-modellen kunnen uit Bestanden worden geïmporteerd. De engine kan alleen modellen uitvoeren die met de meegeleverde llama.cpp-versie compatibel zijn.
- Tekstbestanden, PDF, afbeeldingen en audio kunnen als invoer worden toegevoegd. Afbeeldingen worden lokaal met Vision-OCR verwerkt; audio wordt met lokale Apple-spraakherkenning verwerkt wanneer de gekozen taal en het toestel dit ondersteunen.
- Geen eigen warmtepauze in de app. iOS blijft verantwoordelijk voor geheugenbeheer, thermische regeling en app-uitvoering.

Een taalmodel heeft altijd een eindige context en vereist geheugen en opslag. Als het contextvenster vol is, schuift de actieve modelcontext door; dit wist geen opgeslagen chatberichten. Een onbeperkte context, universele modelcompatibiliteit of onbeperkte fysieke capaciteit kan een iOS-app niet garanderen.

## Openen en bouwen

1. Open `JJS.xcodeproj` op een Mac met Xcode.
2. Selecteer de JJS-app en stel je Apple Development Team in bij Signing & Capabilities.
3. Kies `JJS` en bouw/archiveer voor een iPhone of iPad.
4. Importeer een GGUF-model vanuit Bestanden en stuur een vraag.

Het framework bevat alleen iOS-arm64. Simulator- en macOS-builds zijn daarom niet beschikbaar. Het minimumdeploymenttarget volgt de appconfiguratie; iOS verzorgt de apparaat- en achtergrondlevenscyclus.

## Codemagic

De workflow staat in de root `codemagic.yaml`. Configureer in Codemagic je Apple Developer-integratie, ontwikkelcertificaat en provisioningprofiel voor `nl.jjs.vrij`. De workflow voert eerst `scripts/test_core.sh` uit, past daarna signingprofielen toe en archiveert/exporteert de ondertekende IPA.

Lokaal:

```bash
bash scripts/test_core.sh
bash scripts/build_signed.sh DEVELOPMENT_TEAM=JOUW_TEAM
```

Voor IPA-export moet `JJS_EXPORT_OPTIONS` verwijzen naar een geldig `ExportOptions.plist`.

## Versie 1.1

- Gewone tekstbestanden importeren als volledige inhoud van een nieuw gesprek.
- Eén gesprek of alle gesprekken exporteren als leesbare UTF-8-tekst. Gebruik JSON voor een volledige overdracht met rollen en statussen.
- GGUF downloaden via rechtstreekse bestandslinks, met voortgang in bytes en annuleren. Gesplitste modellen kunnen met één URL per regel samen worden gedownload.
- GGUF importeren vanuit Bestanden en GGUF-bestanden delen/exporteren. Bij een gesplitst model worden alle delen gedeeld.
- Geen extra decoderclassificatiefilter vóór modeluitvoering en geen willekeurig minimum van acht contexttokens. De engine moet het model en een niet-lege context wel daadwerkelijk kunnen laden.
- Modellen zonder chattemplate kunnen directe tekstinvoer gebruiken. Vul `raw` in als template om berichtinhoud zonder rolmarkeringen of extra instructies aan te bieden. Een lege template-instelling gebruikt de modeltemplate indien aanwezig.
- Privacyuitleg en de llama.cpp-MIT-licentie zijn in de app beschikbaar.
- Spraakherkenningscallbacks kunnen een aanvraag niet meer dubbel afronden.

De batchgrootte van 256 is een verwerkingsbuffer, geen limiet voor bericht- of antwoordlengte. Het ophalen van één volgende wachtrijtaak begrenst niet het aantal taken. Het contextvenster blijft eindig; de engine verwerkt langere gesprekken met contextverschuivingen. Een tekstdecoderapp kan niet garanderen dat iedere GGUF-architectuur of ieder niet-tekstmodel uitvoerbaar is.

## Validatie en distributie

De GitHub-workflow draait de coretests en overdrachtstests, compileert een iOS-arm64 Release-archief en controleert de verpakte app. De overdrachtstests gebruiken GGUF-headerfixtures om opslag en netwerkoverdracht te testen, geen daadwerkelijk inferentiemodel. Er is geen iPhone of echt GGUF-model in deze buildomgeving beschikbaar voor end-to-end-inferentietests.

De geleverde IPA is ongetekend. Voor App Store-distributie zijn daarnaast Apple Distribution-ondertekening, provisioning, App Store Connect-gegevens, een publieke privacybeleid- en support-URL, screenshots, leeftijdsclassificatie en beoordeling door Apple nodig. De workflow levert geen bewijs van App Store-toelating of foutloze werking op alle toestellen.

JJS Vrij gebruikt bundle-ID `nl.jjs.vrij` en installeert naast de oorspronkelijke JJS-app. Gebruik de JSON-export/import om bestaande gesprekken over te zetten.
