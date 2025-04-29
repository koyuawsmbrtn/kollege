using Gtk;
using GLib;
using GtkLayerShell;

public class Kollege : Window {
    private Label output_label;
    private uint refresh_interval_seconds;
    private string script_path;

    public Kollege(string script_path, uint interval_seconds = 5, string font_name = "monospace") {
        this.script_path = script_path;
        this.refresh_interval_seconds = interval_seconds;

        // Initialize Layer Shell
        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_layer(this, Layer.BOTTOM);
        GtkLayerShell.set_anchor(this, Edge.BOTTOM, true);
        GtkLayerShell.set_anchor(this, Edge.LEFT, true);
        GtkLayerShell.set_anchor(this, Edge.RIGHT, true);
        GtkLayerShell.set_exclusive_zone(this, 35);  // Fixed: added 'this' as first parameter
        GtkLayerShell.set_margin(this, Edge.TOP, 0);
        GtkLayerShell.set_margin(this, Edge.LEFT, 0);
        GtkLayerShell.set_margin(this, Edge.RIGHT, 0);

        // Make window non-closable and borderless
        this.deletable = false;
        this.decorated = false;
        this.skip_taskbar_hint = true;
        this.skip_pager_hint = true;
        this.set_type_hint(Gdk.WindowTypeHint.DOCK);

        uint bottom_margin = detect_lavalauncher_running() ? 35 : 0;
        GtkLayerShell.set_margin(this, Edge.BOTTOM, (int) bottom_margin);

        // Set a reasonable height while allowing content to determine exact size
        this.set_size_request(-1, 35);  // -1 means natural width, 35px height like typical bars
        this.set_default_size(1920, 35);
        this.opacity = 0.8;
        this.title = "kollege";

        // Label to display output
        output_label = new Label("Loading...");
        output_label.set_justify(Justification.LEFT);
        output_label.set_xalign(0.0f);
        output_label.set_margin_start(10);
        output_label.set_margin_end(10);
        output_label.set_margin_top(10);
        output_label.set_margin_bottom(10);

        var box = new Box(Orientation.VERTICAL, 0);
        box.pack_start(output_label, true, true, 0);
        add(box);

        // Apply font (TODO: Consider updating to newer GTK API in the future)
        var font_desc = Pango.FontDescription.from_string(font_name);
        output_label.override_font(font_desc);  // Deprecated but still functional

        // Show window
        show_all();

        // Timer for periodic refresh
        Timeout.add_seconds(refresh_interval_seconds, () => {
            update_output();
            return true; // repeat
        });

        // Initial output update
        update_output();
    }

    private void update_output() {
        if (script_path == null || script_path.strip() == "") {
            output_label.set_text("Error: Script path is empty");
            return;
        }

        try {
            // Check if the script exists and is executable
            var script_file = File.new_for_path(script_path);
            if (!script_file.query_exists()) {
                output_label.set_text(@"Error: Script file does not exist: $script_path");
                return;
            }

            FileInfo file_info = script_file.query_info("access::*", FileQueryInfoFlags.NONE);
            if (!file_info.get_attribute_boolean("access::can-execute")) {
                output_label.set_text(@"Error: Script is not executable: $script_path");
                return;
            }

            string[] spawn_args = {"bash", script_path};
            string[] spawn_env = Environ.get();
            
            string stdout;
            string stderr;
            int status;

            Process.spawn_sync(null,
                spawn_args,
                spawn_env,
                SpawnFlags.SEARCH_PATH,
                null,
                out stdout,
                out stderr,
                out status);

            if (status == 0) {
                if (stdout.strip() != "") {
                    if (!stdout.validate()) {
                        output_label.set_text("(invalid utf-8 output)");
                    } else {
                        output_label.set_text(stdout.strip());
                    }
                } else {
                    output_label.set_text("(no output)");
                }
            } else {
                output_label.set_text(@"Error (status $status): $stderr");
            }
        } catch (Error e) {
            output_label.set_text(@"Error: $(e.message)");
        }
    }

    private bool detect_lavalauncher_running() {
        try {
            string stdout;
            string stderr;
            int exit_status;

            Process.spawn_sync(
                null,
                new string[] {"pidof", "lavalauncher"},
                null,
                SpawnFlags.SEARCH_PATH,
                null,
                out stdout,
                out stderr,
                out exit_status
            );

            return exit_status == 0;
        } catch (Error e) {
            return false;
        }
    }

    public static int main(string[] args) {
        // Set WAYLAND_DISPLAY environment variable if not set
        Environment.set_variable("GDK_BACKEND", "wayland", true);
        
        Gtk.init(ref args);

        if (args.length < 2) {
            stderr.printf("Usage: kollege <path_to_script> [interval_seconds] [font_name]\n");
            return 1;
        }

        string script_path = args[1];
        uint interval = 5;
        string font = "monospace";

        if (args.length >= 3) {
            interval = uint.parse(args[2]);
        }

        if (args.length >= 4) {
            font = args[3];
        }

        var display = Gdk.Display.get_default();
        if (display == null || GtkLayerShell.is_supported() == false) {
            stderr.printf("Error: This application requires Wayland and GTK Layer Shell support\n");
            return 1;
        }

        var window = new Kollege(script_path, interval, font);
        Gtk.main();
        return 0;
    }
}

