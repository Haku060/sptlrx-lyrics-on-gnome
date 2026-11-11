import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const LYRICS_FILE = '/tmp/sptlrx-lyrics';
const MAX_LENGTH = 75;
const REFRESH_MS = 100;

const LyricsIndicator = GObject.registerClass(
class LyricsIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'sptlrx Lyrics', true);

        this._label = new St.Label({
            text: '',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'sptlrx-lyrics-label',
        });
        this.add_child(this._label);

        this._timeoutId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            REFRESH_MS,
            () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            }
        );

        this._refresh();
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

        if (text.length > MAX_LENGTH)
            text = `${text.slice(0, MAX_LENGTH - 1)}…`;

        this._label.set_text(text);
        this.visible = text.length > 0;
    }

    destroy() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
        super.destroy();
    }
});

export default class SptlrxLyricsExtension extends Extension {
    enable() {
        this._indicator = new LyricsIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator, 1, 'right');
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
