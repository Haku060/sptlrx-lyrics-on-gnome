import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const POSITIONS = ['left', 'center', 'right'];

function addSpinRow(group, settings, key, title, subtitle, lower, upper, step) {
    const row = new Adw.SpinRow({
        title,
        subtitle,
        adjustment: new Gtk.Adjustment({
            lower,
            upper,
            step_increment: step,
            page_increment: step * 10,
        }),
    });
    row.value = settings.get_int(key);
    row.connect('notify::value', () => {
        settings.set_int(key, Math.round(row.value));
    });
    settings.connect(`changed::${key}`, () => {
        row.value = settings.get_int(key);
    });
    group.add(row);
}

export default class MprisLyricsPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        window.set_default_size(560, 640);

        const page = new Adw.PreferencesPage({
            title: 'General',
            icon_name: 'preferences-system-symbolic',
        });
        window.add(page);

        const display = new Adw.PreferencesGroup({
            title: 'Display',
            description: 'Controls the lyrics item in the GNOME top panel.',
        });
        page.add(display);

        addSpinRow(
            display, settings, 'max-length',
            'Maximum text length',
            'Characters shown in the top panel',
            10, 500, 5
        );

        const hideRow = new Adw.SwitchRow({
            title: 'Hide when empty',
            subtitle: 'Hide the label when there is no lyric text',
        });
        settings.bind(
            'hide-when-empty', hideRow, 'active',
            Gio.SettingsBindFlags.DEFAULT
        );
        display.add(hideRow);

        const statusRow = new Adw.SwitchRow({
            title: 'Show playback status',
            subtitle: 'Show paused/stopped messages',
        });
        settings.bind(
            'show-status', statusRow, 'active',
            Gio.SettingsBindFlags.DEFAULT
        );
        display.add(statusRow);

        const iconRow = new Adw.SwitchRow({
            title: 'Always show music icon',
            subtitle: 'Show \u266b before the song title and lyric lines',
        });
        settings.bind(
            'prefix-icon', iconRow, 'active',
            Gio.SettingsBindFlags.DEFAULT
        );
        display.add(iconRow);

        const positionRow = new Adw.ComboRow({
            title: 'Panel position',
            subtitle: 'Which section of the top panel to use',
            model: Gtk.StringList.new(['Left', 'Center', 'Right']),
        });
        positionRow.selected = Math.max(
            0,
            POSITIONS.indexOf(settings.get_string('panel-position'))
        );
        positionRow.connect('notify::selected', () => {
            settings.set_string(
                'panel-position',
                POSITIONS[positionRow.selected] ?? 'right'
            );
        });
        settings.connect('changed::panel-position', () => {
            positionRow.selected = Math.max(
                0,
                POSITIONS.indexOf(settings.get_string('panel-position'))
            );
        });
        display.add(positionRow);

        addSpinRow(
            display, settings, 'panel-index',
            'Panel order',
            'Order among items in the selected section',
            0, 20, 1
        );

        const appearance = new Adw.PreferencesGroup({title: 'Appearance'});
        page.add(appearance);

        addSpinRow(
            appearance, settings, 'font-size',
            'Font size',
            '0 uses the panel default',
            0, 48, 1
        );

        const colorRow = new Adw.ActionRow({
            title: 'Text color',
            subtitle: 'Optional CSS color, e.g. #ffcc00 or red',
        });
        const colorEntry = new Gtk.Entry({
            text: settings.get_string('text-color'),
            valign: Gtk.Align.CENTER,
            width_chars: 14,
        });
        colorEntry.connect('changed', () => {
            settings.set_string('text-color', colorEntry.text);
        });
        settings.connect('changed::text-color', () => {
            if (colorEntry.text !== settings.get_string('text-color'))
                colorEntry.text = settings.get_string('text-color');
        });
        colorRow.add_suffix(colorEntry);
        appearance.add(colorRow);

        const refresh = new Adw.PreferencesGroup({
            title: 'Refresh',
            description: 'How often the extension reads the lyrics file.',
        });
        page.add(refresh);

        addSpinRow(
            refresh, settings, 'refresh-interval-ms',
            'Refresh interval (ms)',
            'Lower is smoother but uses more CPU',
            50, 2000, 10
        );
    }
}
