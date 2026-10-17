# Changelog

## 1.1.0

- Show each alias's category beside its name.
- Add a category dropdown with counts that combines with name and content searches.
- Edit categories in the alias dialog, with suggestions for recorded categories and support for new names and `default`.
- Create aliases in a chosen category and move existing aliases using `alias set category`.
- Ignore category summary counts during recording, and cover moves, persistence and partial send failures in tests.

## 1.0.3

- Fix recording of aliases displayed as `name (colour replace): content`, which previously skipped 19 entries in the 1530-alias export.
- Add large-list regression coverage using synthetic data, including exact colour alias content and persistence.

## 1.0.2

- Add a separate content search field alongside the alias name search. Both filters can be combined and cleared independently.

## 1.0.1

- Add `/aliases_clear` to clear the current character's saved alias list and stop recording without changing aliases on the MUD.

## 1.0.0

- Record multi-column and categorised Discworld alias listings.
- Search a persistent list kept separately for each character.
- Add and edit aliases in a dialog; preserve category and literal MUD arguments.
- Delete individual aliases with confirmation.
- Match Being's Discworld Blorp Recorder's panel styling.
