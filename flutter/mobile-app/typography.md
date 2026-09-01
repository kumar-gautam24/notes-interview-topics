# Typography

One source of truth: [`TextStyleConfig`](../lib/core/theme/text_styles/text_style_config.dart).
One public API: [`AppTextStyles`](../lib/core/theme/text_styles/app_text_styles.dart).

All widget code MUST use `AppTextStyles.xxx()`. Raw `TextStyle(fontSize: ...)` and
raw `SatoshiFont()` / `.fonts.satoshi.xxx()` calls are lint-banned outside
`lib/core/theme/` (see [`tool/check_typography.dart`](../tool/check_typography.dart)).

## Scale

Applied a ~2px bump vs the legacy scale for readability. Body baseline is **16px**.

| Style                    | Size | Weight          | Height | Family            | Use for                              |
| ------------------------ | ---- | --------------- | ------ | ----------------- | ------------------------------------ |
| `display1`               | 48   | Bold (700)      | 1.2    | Satoshi           | Hero headlines, landing titles       |
| `display2`               | 24   | Bold (700)      | 1.2    | Libre Baskerville | Elegant secondary hero, serif titles |
| `display3`               | 32   | Bold (700)      | 1.2    | Satoshi           | Card heroes, modal titles            |
| `display3Satoshi`        | 24   | Bold (700)      | 1.2    | Satoshi           | Sans-serif alt of display2           |
| `heading1`               | 20   | Bold (700)      | 1.3    | Satoshi           | Page / screen headers                |
| `heading2`               | 18   | Bold (700)      | 1.3    | Satoshi           | Section titles, card headers         |
| `title`                  | 18   | Medium (500)    | 1.5    | Satoshi           | Emphasized content titles            |
| `titleSemibold`          | 18   | Semibold (600)  | 1.5    | Satoshi           | Figma-parity between medium & bold   |
| `subtitle` / `title2`    | 16   | Medium (500)    | 1.5    | Satoshi           | Subtitles, list item titles          |
| `transcript`             | 20   | Medium (500)    | 1.5    | Satoshi           | Chat transcripts                     |
| `bodyLarge`              | 18   | Regular (400)   | 1.5    | Satoshi           | Primary body emphasis                |
| `bodyLargeMedium`        | 18   | Medium (500)    | 1.5    | Satoshi           | Medium-weight body large             |
| `bodyLargeSemibold`      | 18   | Semibold (600)  | 1.5    | Satoshi           | Semibold body large                  |
| `bodyLargeBold`          | 18   | Bold (700)      | 1.5    | Satoshi           | Bold body large                      |
| `body`                   | 16   | Regular (400)   | 1.5    | Satoshi           | **Standard body text**               |
| `bodySmallMedium`        | 16   | Medium (500)    | 1.5    | Satoshi           | Medium-weight body                   |
| `bodySemibold`           | 16   | Semibold (600)  | 1.5    | Satoshi           | Semibold body                        |
| `bodySmallBold`          | 16   | Bold (700)      | 1.5    | Satoshi           | Bold body                            |
| `bodySmall`              | 13   | Regular (400)   | 1.5    | Satoshi           | Secondary descriptions, helper text  |
| `tiny`                   | 11   | Regular (400)   | 1.4    | Satoshi           | Timestamps, fine print, timers       |
| `tinyMedium`             | 11   | Medium (500)    | 1.4    | Satoshi           | Same, emphasized                     |
| `button` / `buttonLarge` | 16   | Bold (700)      | 1.5    | Satoshi           | Primary / standard buttons           |
| `buttonSmall`            | 13   | Medium (500)    | 1.5    | Satoshi           | Inline / compact buttons             |
| `labelLarge`             | 18   | Medium (500)    | 1.4    | Satoshi           | Large form labels                    |
| `label`                  | 13   | Bold (700)      | 1.5    | Satoshi           | Small form / metadata labels         |
| `captionMedium`          | 13   | Medium (500)    | 1.5    | Satoshi           | Emphasised captions                  |
| `caption`                | 13   | Regular (400)   | 1.5    | Satoshi           | Standard captions                    |
| `chip`                   | 13   | Medium (500)    | 1.3    | Satoshi           | Chips, tags, badges                  |
| `overline`               | 10   | Medium (500)    | 1.4    | Satoshi           | Caps-label, wide spacing             |

## Override policy

Named styles are the preferred path. When Figma specifies a size/weight/height
that doesn't map cleanly, pass an override on the named style:

```dart
Text('Figma-parity 15px', style: AppTextStyles.body(fontSize: 15));
Text('Heavier subtitle', style: AppTextStyles.subtitle(fontWeight: FontWeight.w700));
```

If an override pattern repeats in 5+ files, promote it to a new named style in
`TextStyleConfig` + `AppTextStyles` rather than leaving it as an ad-hoc override.

## Figma sync

The scale above is the canonical source. Figma typography tokens should mirror
it exactly. When adjusting any row in the table:

1. Update `TextStyleConfig` first.
2. Update the Figma token.
3. Update this doc.
4. Run `dart run tool/check_typography.dart` to confirm no drift re-entered the repo.

## Migration from raw fontSize literals

CI runs `dart run tool/check_typography.dart`. It lists every violation with a
replacement rubric (pass `--fix-hint` locally). Suggested mapping:

```
fontSize: 10, w500          -> AppTextStyles.overline()
fontSize: 11                -> AppTextStyles.tiny()
fontSize: 12, w400          -> AppTextStyles.caption()
fontSize: 12, w500          -> AppTextStyles.captionMedium() / chip()
fontSize: 12, w700          -> AppTextStyles.label()
fontSize: 13, *             -> caption / captionMedium / label / buttonSmall
fontSize: 14, w400          -> AppTextStyles.body()
fontSize: 14, w500          -> AppTextStyles.subtitle()
fontSize: 14, w700          -> AppTextStyles.bodySmallBold() / button()
fontSize: 16, w400          -> AppTextStyles.bodyLarge()
fontSize: 16, w500          -> AppTextStyles.title() / bodyLargeMedium()
fontSize: 16, w700          -> AppTextStyles.bodyLargeBold() / heading2()
fontSize: 18, w500          -> AppTextStyles.title()
fontSize: 18, w700          -> AppTextStyles.heading1()
fontSize: 20                -> AppTextStyles.transcript() / heading1()
fontSize: 24 (serif)        -> AppTextStyles.display2()
fontSize: 24 (sans)         -> AppTextStyles.display3Satoshi()
fontSize: 32                -> AppTextStyles.display3()
fontSize: 48                -> AppTextStyles.display1()
```
