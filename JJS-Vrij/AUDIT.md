# Codecontrole JJS Vrij 2.0.2

Deze controle betreft de acht Swift-bestanden van het zelfstandige project. Het is een broncodecontrole met geautomatiseerde opslag-/overdrachtstests en een iOS-Release-build, geen bewijs van werking op een bepaalde iPhone of met een bepaald GGUF-model.

## Gevonden en aangepast

1. Een geselecteerd `.json`-document werd uitsluitend als JJS-gespreksarchief behandeld. Een geldig gewoon JSON-document leidde daardoor tot een fout. `LibraryVault.importDocument` herkent een ondersteund gespreksarchief en importeert andere leesbare documenten volledig als tekst. UTF-8 en UTF-16 blijven ondersteund.
2. De downloadknop en de downloadmethode weigerden een nieuwe overdracht zolang een vorige liep. Nieuwe GGUF-downloadopdrachten worden nu geaccepteerd en in een wachtrij verwerkt. Er is geen maximumaantal opdrachten ingesteld. Bestanden worden achtereenvolgens verwerkt om afzonderlijke modelgroepen bij elkaar te houden.
3. Bij annuleren vlak voor de opslagcommit kon een import nog worden afgerond. De import controleert annuleren nu ook tijdens het hashen en vóór het zichtbaar maken van de modelgroep. Annuleren verwijdert ook wachtende opdrachten. Een opdracht die ná annuleren wordt aangemeld, kan opnieuw starten.

## Generatie en tokenverwerking

| Code | Betekenis | Controle |
|---|---|---|
| `GGUFRunner.reply`: `while true` | Generatielus | Geen tellervergelijking voor maximumaantal uitvoertokens en geen generatietimer. |
| `llama_vocab_is_eog` | Eindtoken van het geladen model | Beëindigt een antwoord volgens de tokenvocabulary; geen appquotum. |
| `Task.checkCancellation` | Stopknop/taakannulering | Nodig om een expliciet stopverzoek te verwerken. |
| `block = 256` | Native verwerkingsbuffer | Invoer wordt in meerdere batches verwerkt; er is geen cumulatieve grens van 256 tokens. |
| `n_seq_max = 1` | Eén actieve native sequentie | De app bewaart volgende antwoorden in een wachtrij; geen maximumaantal berichten. |
| `active.suffix(...)` | Contextverschuiving | Bij een volle eindige context wordt een deel van de actieve tokencontext opnieuw verwerkt. De opgeslagen gesprekken en de volledige uitvoertekst worden niet hiermee afgekapt. |
| `Int32`/`UInt32` | Gegevenstypen van de native C-interface | Invoer en posities moeten in de gebruikte API passen. Deze representatie is niet onbeperkt. |
| `temperature >= 0` en `isFinite` | Geldige samplingparameter | Weigert ongeldige numerieke instellingen; geen inhoudsfilter. |
| `prefix(length)` bij tokentekst | Door de C-functie teruggegeven bufferlengte | Neemt de daadwerkelijk geschreven bytes over; kapt geen antwoord af op een appbudget. |

## Welke tekst wordt verwerkt?

`Workspace.startQueue` stelt modelberichten samen uit `Letter.text` vóór het betreffende antwoord. Rollen zijn `user` of `assistant`. `GGUFRunner.prompt` gebruikt de modeltemplate, de gekozen template of directe tekst (`raw`). Schermteksten, instellingenlabels, foutdetails, README-bestanden en dit auditdocument worden niet automatisch aan de prompt toegevoegd.

`GGUFRunner` levert gegenereerde tekstfragmenten aan `Workspace.receive`. Die voegt de fragmenten aan het antwoord toe. `LetterView` toont `Text(letter.text)` letterlijk. Status- en foutdetails zijn afzonderlijke UI-gegevens en worden niet als antwoordtekst of als volgende gespreksinhoud ingevoegd. Een door de gebruiker geïmporteerd of als bijlage toegevoegd document is uiteraard wel gekozen gespreksinhoud.

Een GGUF-model kan zelf waarschuwingen of andere tekst genereren. De app verwijdert of vervangt zulke modeltekst niet.

## Import, export en weergave

- Geen ingesteld maximumaantal modellen, gesprekken, berichten of bestandsbytes in de eigen appcode.
- De GGUF-headercontrole en SHA-256-kopiecontrole controleren bestandssoort en kopie-integriteit.
- Padcontroles zorgen dat modelbeheer de bedoelde appmap gebruikt. Ze zijn geen model- of inhoudsblacklist.
- De vijf cijfers in standaard gesplitste GGUF-bestandsnamen dienen om delen van een groep te herkennen, niet om de modelinhoud of omvang te begrenzen.
- De HTTP-statuscontrole verwacht een volledig bestand; een mislukte serverrespons wordt niet als model geïnstalleerd.
- `lineLimit(1...7)` bepaalt alleen de hoogte van het compacte schrijfveld. Het grotere schrijfveld en de opgeslagen berichtinhoud worden niet tot zeven regels beperkt. `lineLimit(2)` toont een verkorte gesprekstitel in de lijst; het wijzigt de opgeslagen titel niet.
- Het versienummer van een eigen JSON-archief bepaalt hoe het wordt geïnterpreteerd. Niet-herkende leesbare documenten kunnen nu als tekst worden geïmporteerd. Een onleesbare/beschadigde interne opslag wordt niet automatisch overschreven.
- Privacytoestemming en beschikbaarheid van lokale Apple-spraakherkenning zijn iOS-voorwaarden. De app schakelt bij gebrek daaraan niet stiekem naar een externe spraakserver.

## Resterende technische grenzen en onzekerheden

De bestaande native `llama.xcframework` is een externe afhankelijkheid en is niet volledig herschreven of universeel gevalideerd. De aanwezige C-chatformatter ondersteunt niet iedere modeltemplate; directe tekstinvoer is daarvoor beschikbaar, maar garandeert geen equivalent gedrag. De tekstdecoder ondersteunt niet automatisch iedere GGUF-architectuur of ieder multimodaal model.

De app moet het model, de context en de gespreksgegevens kunnen laden. RAM, opslag, GPU/CPU, iOS-processcheduling en modelcontext zijn eindig. Lange gesprekken vereisen meer geheugen en opslag; de huidige JSON-opslag serialiseert de bibliotheek bij checkpoints, wat bij grote bibliotheken tijd en tijdelijk geheugen kan kosten. Er is hiervoor geen numerieke appquota ingesteld, maar het is geen garantie van onbeperkte schaalbaarheid.

De tests gebruiken voor modeloverdracht GGUF-headerfixtures, geen volledig inferentiemodel. Niet uitgevoerd: inferentie op een echte iPhone, prestatietests met het door de gebruiker gekozen model, App Store-uploadvalidatie of Apple Review. Er is geen concrete toestelmelding, modelbestandsnaam of reproduceerbaar voorbeeld aangeleverd waarmee het gemelde gedrag op het toestel kan worden bevestigd.

Daarom kan deze controle concrete codeblokkades aantonen en oplossen, maar niet vaststellen dat alle door de gebruiker bedoelde problemen op het toestel zijn verholpen.
