using Gtk;
using GLib;
using GtkLayerShell;
using Vte;  // Add VTE terminal library support

public class Kollege : Window {
    private Terminal terminal;  // Replace Label with VTE Terminal
    private uint refresh_interval_seconds;
    private string script_path;

    public Kollege(string script_path, uint interval_seconds = 5, string font_name = "monospace") {
        Object(type: Gtk.WindowType.TOPLEVEL);
        
        this.script_path = script_path;
        this.refresh_interval_seconds = interval_seconds;

        // Initialize terminal
        terminal = new Terminal();
        terminal.set_size(80, 1);  // Set initial size in characters
        terminal.set_scroll_on_output(true);
        terminal.set_scroll_on_keystroke(true);
        terminal.set_cursor_blink_mode(CursorBlinkMode.OFF);
        
        // Set font using the modern API
        var font_desc = Pango.FontDescription.from_string(font_name);
        terminal.set_font(font_desc);
        
        // Set terminal colors
        var fg = Gdk.RGBA();
        var bg = Gdk.RGBA();
        fg.parse("#ffffff");
        bg.parse("#000000");
        terminal.set_color_foreground(fg);
        terminal.set_color_background(bg);
        
        // Add terminal to window
        this.add(terminal);

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

        uint bottom_margin = detect_lavalauncher_running() ? 35 : 0;
        GtkLayerShell.set_margin(this, Edge.BOTTOM, (int) bottom_margin);

        // Set reasonable size constraints
        var display = get_display();
        var monitor = display.get_primary_monitor() ?? display.get_monitor(0);
        var geometry = monitor.get_geometry();
        
        int max_width = geometry.width;
        int max_height = 200;  // Reasonable max height for output

        this.set_size_request(50, 35);  // Minimum size
        this.set_default_size(max_width, 35);  // Default size
        this.set_resizable(true);  // Allow window to resize based on content

        // Apply size constraints
        Gdk.Geometry size_hints = Gdk.Geometry();
        size_hints.min_width = 50;
        size_hints.min_height = 35;
        size_hints.max_width = max_width;
        size_hints.max_height = max_height;
        this.set_geometry_hints(null, size_hints, Gdk.WindowHints.MIN_SIZE | Gdk.WindowHints.MAX_SIZE);

        // Show all widgets
        show_all();

        // Timer for periodic refresh
        Timeout.add_seconds(refresh_interval_seconds, () => {
            update_output();
            return true;
        });

        update_output();
    }

    private void update_output() {
        if (script_path == null || script_path.strip() == "") {
            terminal.feed("Error: Script path is empty\r\n".data);
            return;
        }

        try {
            var script_file = File.new_for_path(script_path);
            if (!script_file.query_exists()) {
                terminal.feed(@"Error: Script file does not exist: $script_path\r\n".data);
                return;
            }

            FileInfo file_info = script_file.query_info("access::*", FileQueryInfoFlags.NONE);
            if (!file_info.get_attribute_boolean("access::can-execute")) {
                terminal.feed(@"Error: Script is not executable: $script_path\r\n".data);
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
                terminal.reset(true, true);  // Clear terminal
                terminal.feed(stdout.data);  // Feed output directly to terminal
            } else {
                terminal.feed(@"Error (status $status): $stderr\r\n".data);
            }
        } catch (Error e) {
            terminal.feed(@"Error: $(e.message)\r\n".data);
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

        var app_window = new Kollege(script_path, interval, font);
        Gtk.main();
        return 0;
    }
}

