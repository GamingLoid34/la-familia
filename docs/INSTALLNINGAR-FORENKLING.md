# Förenklade inställningar, 2026-10-22

Android 1.14.4 (57) och webb 1.0.4+31 samlar inställningarna under fyra öppningsbara grupper: Min vy, Påminnelser, Familjen och Om appen. Profil och utloggning är direkt åtkomliga. Familjen och storskärmen visas endast för föräldrar. Webbens verktygsingång finns kvar, med kalenderanpassad text i pilotläget.

Vanlig vy/Fokus ersätter Allt/Fokus. Startvyn förklaras och skiljs från Lugnare utseende, som tidigare hette Lågstimuli-läge. Lugnare utseende flyttas från webbens notisinställningar till Min vy. Påminnelser namnges efter när de kommer, och texten skiljer enhetsval från kontoval. Webbens webRemindersEnabled gäller kontot i anslutna webbläsare, vilket nu framgår. Plats för väder ersätter Hemposition. Androids färgval och deras beroende av lugnare utseende förklaras. Webbens Om visar den verkliga byggversionen i stället för fast 1.0.0.

Rutiner, matpreferenser, Växtkoll-kopplingen och sysslonotisval döljs i kalenderpiloten där de finns. Sparade värden, behörigheter, skrivvägar och påminnelsernas beteende ändras inte. Inga konton, data, regler eller backendfunktioner ändras. Storskärmen behåller sin ingång och sin nuvarande funktionalitet; dess genomgång är nästa separata steg.

Verifiering: 990 Androidtester och DevDebug-bygge godkända. 431 Fluttertester passerade, inklusive ett nytt widgetprov på 320 px som öppnar/stänger en inställningsgrupp utan att ändra något sparat val. Flutter analyze utan anmärkningar. Inget fysiskt telefonprov har körts här.

APK: vardag-dev-1.14.4-installningar.apk. SHA-256: 6001f19248e60bb17684d2b9959296e4590bb76830438e2c6b299c8dff9eba57.

APK levererad privat till Drive och verifierad mot filstorlek/hash: https://drive.google.com/file/d/1dD5k-CG_9kDzyFDTP6aIw1rFspVvf4W4/view. Paket com.lafamilia.app.dev, samma signeringscertifikat som föregående version, installerbar som uppdatering.

Webb 1.0.4+31 byggd och publicerad på https://la-familia-5d9f5.web.app. Åtta HTTP-resurser jämfördes byte för byte med det frysta releasepaketet /home/oscar/utveckling/vardag-pwa-leveranser/1.0.4-31; samtliga gav HTTP 200 och matchade. Endast Hosting publicerades. Föregående paket 1.0.3-30 finns kvar.
