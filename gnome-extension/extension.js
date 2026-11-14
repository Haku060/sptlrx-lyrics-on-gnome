import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const LYRICS_FILE = '/tmp/mpris-lyrics';

const LyricsIndicator = GObject.registerClass(
class LyricsIndicator extends PanelMenu.Button {
    _init(settings, onOpenPreferences) {
        // 0.5 centers the popup under the panel item. The shell clamps it
        // to the monitor edges, so this also works on other resolutions.
        super._init(0.5, 'MPRIS Lyrics', false);

        this._settings = settings;
        this._onOpenPreferences = onOpenPreferences;
        this._timeoutId = 0;
        this._settingsChangedId = this._settings.connect(
            'changed',
            (_settings, key) => this._onSettingsChanged(key)
        );

        this._label = new St.Label({
            text: '',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'mpris-lyrics-label',
        });
        this.add_child(this._label);

        this._buildMenu();
        this._updateStyle();
        this._startTimer();
        this._refresh();
    }

    _buildMenu() {
        this.menu.removeAll();

        const settingsItem = new PopupMenu.PopupImageMenuItem(
            'Settings',
            'preferences-system-symbolic'
        );
        settingsItem.connect('activate', () => {
            this.menu.close();
            this._onOpenPreferences?.();
        });
        this.menu.addMenuItem(settingsItem);
    }

    _startTimer() {
        this._stopTimer();
        const interval = Math.max(
            50,
            this._settings.get_int('refresh-interval-ms')
        );
        this._timeoutId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            interval,
            () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    _stopTimer() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
    }

    _onSettingsChanged(key) {
        if (key === 'refresh-interval-ms')
            this._startTimer();
        else if (key === 'font-size' || key === 'text-color')
            this._updateStyle();

        if (key === 'max-length' ||
            key === 'hide-when-empty' ||
            key === 'show-status' ||
            key === 'prefix-icon')
            this._refresh();
    }

    _updateStyle() {
        const fontSize = this._settings.get_int('font-size');
        const color = this._settings.get_string('text-color').trim();
        let style = '';

        if (fontSize > 0)
            style += `font-size: ${fontSize}px;`;

        // Keep the setting to a plain CSS color value.
        if (color && /^[#a-zA-Z0-9(),.%\s-]+$/.test(color))
            style += `color: ${color};`;

        this._label.set_style(style);
    }

    _refresh() {
        let text = '';
        try {
            const [ok, contents] = GLib.file_get_contents(LYRICS_FILE);
            if (ok)
                text = new TextDecoder('utf-8').decode(contents).trim();
        } catch (e) {
            // The pipe may not have written the file yet.
        }

        const isStatusText =
            text.startsWith('\u23f8') || text.startsWith('\u23f9');
        let statusHidden = false;
        if (!this._settings.get_boolean('show-status') && isStatusText) {
            text = '';
            statusHidden = true;
        }

        const hideWhenEmpty = this._settings.get_boolean('hide-when-empty');

        // If the pipe has no line to show (for example the service is
        // restarting), show the playing icon instead of an empty block.
        if (text.length === 0 && !statusHidden && !hideWhenEmpty)
            text = '\u266b';

        const isIconOnly = text === '\u266b';
        if (!statusHidden && !isStatusText && !isIconOnly &&
            text.length > 0 &&
            this._settings.get_boolean('prefix-icon'))
            text = `\u266b ${text}`;

        const maxLength = Math.max(
            10,
            this._settings.get_int('max-length')
        );
        if (text.length > maxLength)
            text = `${text.slice(0, maxLength - 1)}\u2026`;

        this._label.set_text(text);

        if (statusHidden)
            this.visible = false;
        else if (hideWhenEmpty)
            this.visible = text.length > 0;
        else
            this.visible = true;
    }

    destroy() {
        this._stopTimer();
        if (this._settingsChangedId) {
            this._settings.disconnect(this._settingsChangedId);
            this._settingsChangedId = 0;
        }
        super.destroy();
    }
});

export default class MprisLyricsExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._indicator = null;
        this._roleCounter = 0;
        this._positionChangedId = this._settings.connect(
            'changed::panel-position',
            () => this._rebuildIndicator()
        );
        this._indexChangedId = this._settings.connect(
            'changed::panel-index',
            () => this._rebuildIndicator()
        );
        this._addIndicator();
    }

    _addIndicator() {
        const position = this._settings.get_string('panel-position');
        const index = this._settings.get_int('panel-index');

        // Reusing the same role after moving the indicator can leave the
        // old role registered in Main.panel.statusArea. Use a fresh role
        // each time so the item can actually move between panel sections.
        const role = `${this.uuid}-${++this._roleCounter}`;
        this._indicator = new LyricsIndicator(
            this._settings,
            () => this.openPreferences()
        );
        Main.panel.addToStatusArea(role, this._indicator, index, position);
    }

    _rebuildIndicator() {
        if (this._indicator) {
            const old = this._indicator;
            this._indicator = null;
            const parent = old.get_parent();
            if (parent)
                parent.remove_child(old);
            old.destroy();
        }
        this._addIndicator();
    }

    disable() {
        if (this._positionChangedId) {
            this._settings.disconnect(this._positionChangedId);
            this._positionChangedId = 0;
        }
        if (this._indexChangedId) {
            this._settings.disconnect(this._indexChangedId);
            this._indexChangedId = 0;
        }
        this._indicator?.destroy();
        this._indicator = null;
        this._settings = null;
    }
}
