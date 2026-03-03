package app.loreline.sdl3sample;

import org.libsdl.app.SDLActivity;

/**
 * Loreline SDL3 Sample — Android entry point.
 *
 * Extends SDLActivity which handles:
 * - Native library loading (libmain.so, libSDL3.so)
 * - GL/Vulkan surface creation
 * - Input event forwarding to SDL
 * - Activity lifecycle management
 */
public class LorelineActivity extends SDLActivity {

    @Override
    protected String[] getLibraries() {
        return new String[] {
            "SDL3",
            "loreline",
            "main"
        };
    }
}
