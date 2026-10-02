# ShaguDPS Details

Erweiterung für [ShaguDPS](https://github.com/shagu/ShaguDPS) (WoW 1.12): detaillierte Aufschlüsselung pro Zauber und pro Ziel.

## Was es zeigt
Für jeden Zauber bzw. jede Fähigkeit eines Spielers:
- Anzahl der Treffer
- Mittelwert und Maximum
- Crit-Quote
- Verteilung auf die Ziele

## Bedienung
- Klick auf einen Balken im ShaguDPS-Fenster öffnet die Details für diesen Spieler.
- `/sdd` öffnet das Fenster direkt.

## Wie es funktioniert
ShaguDPS speichert pro Zauber nur die Summe. Dieses Addon legt die zusätzlichen Daten daneben an, ohne ShaguDPS selbst zu verändern. Es hängt sich an `parser.AddData` und prüft die Kampflog-Rohmeldung vorher gegen die Crit-Muster. Ein Update von ShaguDPS überschreibt also nichts.

Schriftgröße und Deckkraft werden von `ShaguDPS_UI` übernommen, falls installiert.

## Voraussetzungen
ShaguDPS

## Gespeicherte Daten
`ShaguDPS_Detail_Config` (pro Charakter)
