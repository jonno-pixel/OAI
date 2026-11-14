# ClockChat voor iPhone

Native SwiftUI-startproject, versie 0.1.0. Gebaseerd op jouw ClockChat.pyw.
Geen Python, webview of externe Swift-bibliotheken nodig.

## Wat je krijgt

- Moderne lichte/donkere interface, systeemmaterialen, aanpasbare tekstgrootte en Nederlandse bediening.
- Chat met OpenAI, Ollama en LM Studio via hun OpenAI-compatibele Chat Completions API.
- Streaming tekst, stoppen, selecteerbare tekst en eenvoudige Markdown-weergave.
- Nieuwe gesprekken, lokale geschiedenis en verwijderen via naar links vegen.
- Instellingen per dienst, verbindingstest en ophalen van modellen.
- Sleutels per dienst in Keychain; niet in het project of gespreksbestand.
- Een compacte live klok als verwijzing naar het oorspronkelijke ontwerp.

Dit is broncode, nog geen gebouwde, ondertekende of op een iPhone geteste app.
De minimumversie is op jouw verzoek iOS 27.0, voor iPhone. Er worden geen
onbevestigde iOS-27-API's gebruikt. Xcode met iOS SDK 27 of nieuwer is
noodzakelijk om deze configuratie te bouwen. Ook je iPhone moet iOS 27 of
nieuwer draaien.

## Begin hier vanaf Windows

1. Pak het ZIP-bestand uit. De map bevat ClockChat.xcodeproj, ClockChat/,
   scripts/ en .github/. Bewaar ook de verborgen .github-map.
2. Voor een cloud-build: maak zelf een privé-GitHub-repository aan en zet de
   inhoud van deze map in de hoofdmap van die repository. Er wordt vanuit
   deze chat niets naar GitHub geüpload.
3. In GitHub: Actions → Build iPhone IPA → Run workflow. De workflow gebruikt
   een macOS-runner, die afhankelijk van je account geld of minuten kan kosten.
4. De workflow gebruikt de GitHub-runner `xcode-27` en toont de geïnstalleerde
   Xcode/SDK. Deze runner is een preview en kan instabiel zijn of wachttijd hebben.
   Als de SDK lager dan 27 is, stopt de build met uitleg.
5. Na een geslaagde build download je het artifact ClockChat-unsigned-IPA.
   Pak het artifact uit; daarin staat ClockChat-unsigned.ipa.
6. Importeer die IPA met AltStore Classic volgens de actuele officiële
   Windows-handleiding: https://faq.altstore.io/ . AltServer moet ingesteld
   zijn en je iPhone bereikbaar. AltStore moet de app nog ondertekenen.

Een workflow in een submap van een repository wordt niet automatisch herkend.
Plaats .github/workflows/build-ios.yml dus echt in de repository-hoofdmap.
De unsigned IPA is niet rechtstreeks installeerbaar via Safari. Ondertekenen
kan tegen AltStore-, Apple-account- of appaantallimieten aanlopen. Met een
gratis Apple-account is de geldigheid doorgaans zeven dagen. Deel je
Apple-wachtwoord, API-sleutels of verificatiecodes niet in chat of GitHub.

### Op een Mac of cloud-Mac

Installeer/kies passende Xcode en open ClockChat.xcodeproj. De gedeelde scheme
heet ClockChat. Voor een simulator kies je een iOS 27+-simulator en Run.
Voor een AltStore-pakket voer je vanuit de projectmap uit:

```bash
bash scripts/build-ipa.sh
```

Resultaat: build/ClockChat-unsigned.ipa. Dit script gebruikt geen Apple-account
of certificaat. AltStore verzorgt de latere ondertekening. Voor normale
installatie vanuit Xcode kies je zelf een unieke bundle identifier en team
onder Signing & Capabilities; com.example.clockchat is een voorbeeld.

Wil je bewust ook een oudere iOS-versie ondersteunen? Verlaag de iOS Deployment
Target in zowel Debug als Release. De gebruikte interface-API's richten zich
op iOS 17+, maar ook die variant moet nog met Xcode worden gebouwd en getest.

## Verbinden

### OpenAI

Instellingen → OpenAI. Laat https://api.openai.com/v1 staan. Vul je eigen
OpenAI API-sleutel in, test de verbinding en kies een model dat Chat Completions
en tekststreaming ondersteunt. Een ChatGPT-abonnement levert geen API-tegoed.
De modellenlijst kan ook audio-, embedding- en andere niet-chatmodellen bevatten.
Een geslaagde modellenlijst bewijst bereikbaarheid en toegang tot die lijst;
het garandeert geen chatrechten of voldoende tegoed voor elk model.

### Ollama

Installeer Ollama op je pc en download een chatmodel. De server moet op je
lokale netwerk luisteren (bijvoorbeeld via OLLAMA_HOST=0.0.0.0:11434; herstart
Ollama na wijzigen). Stel alleen de benodigde firewalltoegang op je private
netwerk in. Zoek je pc's IPv4-adres met ipconfig en vul bijvoorbeeld in:
http://192.168.1.42:11434/v1 . Haal de modellenlijst op en kies je model.

### LM Studio

Laad een chatmodel, start de lokale OpenAI-compatibele server en schakel de
LAN-optie in. Gebruik bijvoorbeeld http://192.168.1.42:1234/v1 . Als je
server authenticatie gebruikt, vul je de bijbehorende sleutel in.

Voor beide lokale diensten: iPhone en pc moeten elkaar kunnen bereiken.
Geef de app op je iPhone toestemming voor het lokale netwerk. localhost en
127.0.0.1 verwijzen op een iPhone naar de iPhone, niet naar de Windows-pc.
Je computer moet aanstaan en de server moet draaien. Stel geen poorten open
naar het publieke internet. Gebruik onderweg een private VPN met correct
bereikbare adressen; bij externe servers HTTPS. HTTP is alleen bedoeld voor
vertrouwde lokale netwerken. Netwerkbeleid van iOS kan per adres verschillen;
gebruik zo nodig een lokale .local-hostnaam of een HTTPS-endpoint.

## Gegevens en beperkingen

Gesprekken en niet-geheime instellingen staan in Application Support, beschermd
met iOS-bestandsbeveiliging. Ze zijn niet aanvullend versleuteld door de app en
kunnen in een toestelback-up terechtkomen. Sleutels zijn alleen toegankelijk op
dit toestel wanneer het ontgrendeld is. Er is geen iCloud-sync, eigen server,
telemetrie of appvergrendeling. Je gekozen dienst ontvangt je bericht en de
volledige niet-onderbroken tekstgeschiedenis van het huidige gesprek, ook als
je in datzelfde gesprek naar een andere dienst wisselt. Begin een nieuw gesprek
als je die geschiedenis niet naar een andere dienst wilt sturen.

Een gestopt/onvolledig antwoord blijft zichtbaar met een aanduiding en wordt
niet als compleet antwoord naar de server teruggestuurd. Er is geen automatische
retry (dat voorkomt onbedoelde dubbele API-kosten). Er zijn nog geen bijlagen,
spraak, afbeeldingen, tools, internetzoeken, tokenlimieten per model, export of
berichtbewerking. Lange gesprekken kunnen de contextlimiet van een model raken.
De app bootst de ChatGPT-app niet volledig na en gebruikt geen ChatGPT-login.

## Controle vóór dagelijks gebruik

Zie CONTROLE.md. Er zijn in deze omgeving geen Xcode, Apple SDK of simulator;
compilatie, ondertekening, netwerkaanvragen naar jouw diensten en installatie
zijn niet uitgevoerd. De meegeleverde controle geeft precies aan wat wel is
nagekeken. Bewaar belangrijke gesprekken ook buiten deze eerste versie.
