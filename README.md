# FlickerGuard

FlickerGuard is for people who experience discomfort from PWM flickering on the new OLED MacBook Pro displays. PWM (pulse-width modulation) controls brightness by rapidly pulsing the display’s light output, which can bother people sensitive to flicker.

FlickerGuard keeps hardware brightness at 100% and dims the screen in software to avoid hardware dimming that may introduce PWM flicker. Control brightness from the menu bar with a slider, the keyboard brightness keys, or automatic adjustment to ambient light.

Requires **macOS 27 or later** and a **14-inch or 16-inch MacBook Pro with a PROLED XDR (OLED) display**.

## Install

1. [Download FlickerGuard](https://github.com/tcrouzet/FlickerGuard/releases) and choose **FlickerGuard.app.zip** under Assets.
2. Unzip it and move **FlickerGuard.app** to **Applications**.
3. Open the app. Its sun icon appears in the menu bar.

The app is free and is not notarized by Apple. If macOS blocks it, open **System Settings → Privacy & Security → Open Anyway** after the blocked launch. See [Apple’s instructions](https://support.apple.com/en-us/102445).

## Use

Click the sun icon, then **Enable**. On first activation, allow FlickerGuard in **System Settings → Privacy & Security → Accessibility**, then enable it again. This permission lets the app handle the brightness keys.

- **Software brightness:** drag the slider or use the brightness keys. Lower values make the screen darker; 100% removes software dimming.
- **Automatic adjustment:** follows ambient light and ignores small variations. Moving the slider or pressing a brightness key turns it off, keeping your chosen level fixed. Measured ambient light is shown in lux below the switch.
- **Hardware brightness:** shows the screen’s hardware level, held at 100% while FlickerGuard is active.
- **Disable:** restores your previous macOS brightness and automatic brightness setting.

FlickerGuard resumes at the same software level after sleep or closing the lid. It ignores temporary ambient light changes caused by opening and closing the Mac.

## Start with your Mac

Turn on **Launch at login**. The app opens in the menu bar when you sign in; click **Enable** to activate dimming.

The interface follows your macOS app language and is available in English and French.

## Need help?

If the screen is too bright in automatic mode, move the slider to a comfortable level. This switches to manual mode.

If the app reports no compatible OLED display, your screen is not currently supported. FlickerGuard leaves its settings unchanged.

For other problems, choose **Copy diagnostic** from the **…** menu and include it in a [GitHub issue](https://github.com/tcrouzet/FlickerGuard/issues).

[MIT license](LICENSE).
