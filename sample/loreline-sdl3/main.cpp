/*
 * Loreline SDL3 Sample — CoffeeShop
 *
 * Cross-platform graphical app that runs the CoffeeShop story using SDL3
 * for rendering and stb_truetype for text. Matches the visual design of
 * the Loreline web and Unity samples.
 *
 * Platforms: macOS, Linux, Windows, iOS, Android
 *
 * Build with CMake (see CMakeLists.txt) or use the build scripts:
 *   ./build-mac.sh    ./build-linux.sh    build-windows.bat
 */

/* ══════════════════════════════════════════════════════════════════════════════
 *  INCLUDES
 * ══════════════════════════════════════════════════════════════════════════════ */

#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "Loreline.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include <string>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <cmath>


/* ══════════════════════════════════════════════════════════════════════════════
 *  THEME CONSTANTS
 *
 *  Dark theme palette matching the Loreline website playground preview.
 *  See: sample/loreline-web/index.html :root variables.
 * ══════════════════════════════════════════════════════════════════════════════ */

struct Color { Uint8 r, g, b, a; };

static const Color COL_BG         = { 0x15, 0x13, 0x1b, 0xff }; /* bg-card   */
static const Color COL_TEXT       = { 0xf0, 0xee, 0xf5, 0xff }; /* text      */
static const Color COL_TEXT_MUTED = { 0xa0, 0x9c, 0xb0, 0xff }; /* narrative */
static const Color COL_TEXT_DIM   = { 0x6b, 0x65, 0x80, 0xff }; /* play-again*/
static const Color COL_BORDER    = { 0x2e, 0x2a, 0x3a, 0xff }; /* borders   */
static const Color COL_PURPLE    = { 0x8b, 0x5c, 0xf6, 0xff }; /* accent    */
static const Color COL_GLOW      = { 0x8b, 0x5c, 0xf6, 0x1a }; /* 10% alpha */

/* Character-name gradient: 135deg #ff5eab 0% → #8b5cf6 40% → #56a0f6 100% */
static const Color GRAD_START = { 0xff, 0x5e, 0xab, 0xff };
static const Color GRAD_MID   = { 0x8b, 0x5c, 0xf6, 0xff };
static const Color GRAD_END   = { 0x56, 0xa0, 0xf6, 0xff };
static const float GRAD_MID_STOP = 0.4f;

/* Timing (seconds) */
static const double DELAY_DIALOGUE   = 0.6;   /* auto-advance between lines  */
static const double DELAY_CHOICES    = 0.25;  /* pause before showing choices */
static const double DELAY_PLAY_AGAIN = 0.5;   /* pause before play-again btn */
static const double ANIM_FADEIN      = 0.45;  /* fade-in duration            */
static const double ANIM_CHOICE_P2   = 0.3;   /* phase 2 start (slide up)    */
static const double ANIM_CHOICE_P3   = 0.7;   /* phase 3 start (finalize)    */

/* Layout (logical pixels — scaled by DPI) */
static const float CONTENT_MAX_WIDTH = 700.0f;
static const float PADDING_TOP       = 32.0f;
static const float PADDING_SIDE      = 24.0f;
static const float LINE_HEIGHT_MULT  = 1.35f;
static const float BTN_LINE_HEIGHT_MULT = 1.2f; /* tighter line height inside buttons */
static const float NARRATIVE_MARGIN  = 14.0f;  /* margin-bottom after narrative */
static const float DIALOGUE_MARGIN   = 10.0f;  /* margin-bottom after dialogue  */
static const float CHOICE_MARGIN_TOP = 8.0f;   /* margin-top before choices     */
static const float CHOICE_GAP        = 6.0f;   /* gap between choice buttons    */
static const float CHOICE_PAD_X      = 14.0f;  /* horizontal padding in buttons */
static const float CHOICE_PAD_Y      = 9.0f;   /* vertical padding in buttons   */
static const float BTN_TEXT_OFFSET_Y = 2.0f;   /* nudge button text down for visual centering */
static const float CHOICE_SEL_MARGIN = 19.0f;  /* margin-bottom after collapsed choice */
static const float PLAYAGAIN_MARGIN  = 18.0f;

/* Font sizes (logical pixels) */
static const float FONT_SIZE_NARRATIVE = 24.0f; /* narrative (italic reads smaller) */
static const float FONT_SIZE_TEXT      = 21.0f; /* dialogue / UI text */
static const float FONT_SIZE_CHOICE    = 16.0f;
static const float FONT_SIZE_SMALL     = 15.0f;


/* ══════════════════════════════════════════════════════════════════════════════
 *  FONT ATLAS
 *
 *  Uses stb_truetype's pack API to bake glyphs into a texture atlas at
 *  startup. Covers Basic Latin + Latin-1 Supplement (U+0020–U+00FF) and
 *  General Punctuation (U+2000–U+206F) for em-dash, curly quotes, etc.
 *  Each font (narrative italic, UI regular, UI semibold) gets its own atlas.
 * ══════════════════════════════════════════════════════════════════════════════ */

static const int ATLAS_SIZE = 1024;

/* Unicode ranges baked into the atlas */
#define RANGE_BASIC_START 0x20
#define RANGE_BASIC_COUNT (0x100 - 0x20)  /* U+0020..U+00FF: 224 chars */
#define RANGE_PUNCT_START 0x2000
#define RANGE_PUNCT_COUNT (0x2070 - 0x2000)  /* U+2000..U+206F: 112 chars */

struct FontAtlas {
    SDL_Texture* texture;
    stbtt_packedchar glyphsBasic[RANGE_BASIC_COUNT]; /* U+0020..U+00FF */
    stbtt_packedchar glyphsPunct[RANGE_PUNCT_COUNT]; /* U+2000..U+206F */
    float fontSize;       /* baked size in pixels */
    float ascent;         /* pixels above baseline */
    float descent;        /* pixels below baseline (negative) */
    float lineHeight;     /* fontSize * LINE_HEIGHT_MULT */
    unsigned char* ttfData;
};

static bool loadFontAtlas(FontAtlas* fa, SDL_Renderer* renderer,
                          const char* ttfPath, float fontSize)
{
    fa->fontSize = fontSize;
    fa->lineHeight = fontSize * LINE_HEIGHT_MULT;
    fa->texture = NULL;
    fa->ttfData = NULL;

    /* Load TTF file via SDL for cross-platform asset support */
    SDL_IOStream* io = SDL_IOFromFile(ttfPath, "rb");
    if (!io) {
        SDL_Log("Failed to open font: %s", ttfPath);
        return false;
    }
    Sint64 size = SDL_GetIOSize(io);
    if (size <= 0) { SDL_CloseIO(io); return false; }

    fa->ttfData = (unsigned char*)SDL_malloc((size_t)size);
    SDL_ReadIO(io, fa->ttfData, (size_t)size);
    SDL_CloseIO(io);

    /* Pack glyphs into a bitmap using stbtt_PackFontRanges for multiple
     * Unicode ranges (Basic Latin + Latin-1 Supplement, General Punctuation) */
    unsigned char* bitmap = (unsigned char*)SDL_calloc(1, ATLAS_SIZE * ATLAS_SIZE);

    stbtt_pack_context spc;
    stbtt_PackBegin(&spc, bitmap, ATLAS_SIZE, ATLAS_SIZE, 0, 1, NULL);
    stbtt_PackSetOversampling(&spc, 1, 1);

    stbtt_pack_range ranges[2];
    ranges[0].font_size = fontSize;
    ranges[0].first_unicode_codepoint_in_range = RANGE_BASIC_START;
    ranges[0].array_of_unicode_codepoints = NULL;
    ranges[0].num_chars = RANGE_BASIC_COUNT;
    ranges[0].chardata_for_range = fa->glyphsBasic;
    ranges[1].font_size = fontSize;
    ranges[1].first_unicode_codepoint_in_range = RANGE_PUNCT_START;
    ranges[1].array_of_unicode_codepoints = NULL;
    ranges[1].num_chars = RANGE_PUNCT_COUNT;
    ranges[1].chardata_for_range = fa->glyphsPunct;

    stbtt_PackFontRanges(&spc, fa->ttfData, 0, ranges, 2);
    stbtt_PackEnd(&spc);

    /* Get font metrics */
    stbtt_fontinfo info;
    stbtt_InitFont(&info, fa->ttfData, 0);
    int ascent, descent, lineGap;
    stbtt_GetFontVMetrics(&info, &ascent, &descent, &lineGap);
    float scale = stbtt_ScaleForPixelHeight(&info, fontSize);
    fa->ascent = ascent * scale;
    fa->descent = descent * scale;

    /* Convert single-channel bitmap to RGBA for SDL.
     * SDL_PIXELFORMAT_RGBA8888: R=bits 24-31, G=16-23, B=8-15, A=0-7 */
    Uint32* rgba = (Uint32*)SDL_malloc(ATLAS_SIZE * ATLAS_SIZE * 4);
    for (int i = 0; i < ATLAS_SIZE * ATLAS_SIZE; i++) {
        Uint8 a = bitmap[i];
        rgba[i] = 0xFFFFFF00u | a; /* white (RGB=0xFF) with alpha from bitmap */
    }
    SDL_free(bitmap);

    SDL_Surface* surface = SDL_CreateSurfaceFrom(
        ATLAS_SIZE, ATLAS_SIZE, SDL_PIXELFORMAT_RGBA8888,
        rgba, ATLAS_SIZE * 4);
    if (surface) {
        fa->texture = SDL_CreateTextureFromSurface(renderer, surface);
        SDL_SetTextureBlendMode(fa->texture, SDL_BLENDMODE_BLEND);
        SDL_SetTextureScaleMode(fa->texture, SDL_SCALEMODE_LINEAR);
        SDL_DestroySurface(surface);
    }
    SDL_free(rgba);

    return fa->texture != NULL;
}

static void freeFontAtlas(FontAtlas* fa) {
    if (fa->texture) { SDL_DestroyTexture(fa->texture); fa->texture = NULL; }
    if (fa->ttfData) { SDL_free(fa->ttfData); fa->ttfData = NULL; }
}

/* Decode one UTF-8 codepoint starting at s[pos]. Returns byte count consumed. */
static int decodeUTF8(const char* s, int pos, int len, int* cp) {
    unsigned char c = (unsigned char)s[pos];
    if (c < 0x80) { *cp = c; return 1; }
    if (c < 0xC0) { *cp = '?'; return 1; } /* stray continuation byte */
    if (c < 0xE0 && pos + 1 < len) {
        *cp = ((c & 0x1F) << 6) | ((unsigned char)s[pos+1] & 0x3F);
        return 2;
    }
    if (c < 0xF0 && pos + 2 < len) {
        *cp = ((c & 0x0F) << 12) | (((unsigned char)s[pos+1] & 0x3F) << 6)
              | ((unsigned char)s[pos+2] & 0x3F);
        return 3;
    }
    if (pos + 3 < len) {
        *cp = ((c & 0x07) << 18) | (((unsigned char)s[pos+1] & 0x3F) << 12)
              | (((unsigned char)s[pos+2] & 0x3F) << 6)
              | ((unsigned char)s[pos+3] & 0x3F);
        return 4;
    }
    *cp = '?'; return 1;
}

/* Look up the packed glyph for a Unicode codepoint, falling back to '?' */
static const stbtt_packedchar* getGlyph(const FontAtlas* fa, int cp) {
    if (cp >= RANGE_BASIC_START && cp < RANGE_BASIC_START + RANGE_BASIC_COUNT)
        return &fa->glyphsBasic[cp - RANGE_BASIC_START];
    if (cp >= RANGE_PUNCT_START && cp < RANGE_PUNCT_START + RANGE_PUNCT_COUNT)
        return &fa->glyphsPunct[cp - RANGE_PUNCT_START];
    return &fa->glyphsBasic['?' - RANGE_BASIC_START];
}

/* Measure the width of a UTF-8 string in pixels */
static float measureText(const FontAtlas* fa, const char* text, int len) {
    float x = 0;
    int i = 0;
    while (i < len) {
        int cp;
        i += decodeUTF8(text, i, len, &cp);
        if (cp < 32) cp = '?';
        x += getGlyph(fa, cp)->xadvance;
    }
    return x;
}

/* Draw a string at (x, y=baseline), with a given color. Returns advance. */
static float drawText(SDL_Renderer* renderer, const FontAtlas* fa,
                      float x, float y, const char* text, int len,
                      Color color)
{
    float startX = x;
    SDL_SetTextureColorMod(fa->texture, color.r, color.g, color.b);
    SDL_SetTextureAlphaMod(fa->texture, color.a);

    int i = 0;
    while (i < len) {
        int cp;
        i += decodeUTF8(text, i, len, &cp);
        if (cp < 32) cp = '?';
        const stbtt_packedchar* g = getGlyph(fa, cp);

        float gx = x + g->xoff;
        float gy = y + g->yoff;
        float gw = (float)(g->x1 - g->x0);
        float gh = (float)(g->y1 - g->y0);

        SDL_FRect src = { (float)g->x0, (float)g->y0, gw, gh };
        SDL_FRect dst = { gx, gy, gw, gh };
        SDL_RenderTexture(renderer, fa->texture, &src, &dst);

        x += g->xadvance;
    }
    return x - startX;
}

/* Draw a string with per-character gradient (for character names) */
static float drawTextGradient(SDL_Renderer* renderer, const FontAtlas* fa,
                              float x, float y, const char* text, int len,
                              Uint8 alpha)
{
    if (len <= 0) return 0;
    float totalWidth = measureText(fa, text, len);
    if (totalWidth < 1.0f) return 0;

    float startX = x;
    int i = 0;
    while (i < len) {
        int cp;
        i += decodeUTF8(text, i, len, &cp);
        if (cp < 32) cp = '?';
        const stbtt_packedchar* g = getGlyph(fa, cp);

        /* Compute gradient position for this character.
         * Map to 0.30–0.70 range (not full 0–1) to approximate the 135°
         * diagonal angle effect, matching the Unity sample's softer look. */
        float charPos = (x - startX + g->xadvance * 0.5f) / totalWidth;
        float charCenter = 0.30f + charPos * 0.40f;
        /* Map through the 3-stop gradient */
        Uint8 r, gv, b;
        if (charCenter <= GRAD_MID_STOP) {
            float t = charCenter / GRAD_MID_STOP;
            r = (Uint8)(GRAD_START.r + (GRAD_MID.r - GRAD_START.r) * t);
            gv = (Uint8)(GRAD_START.g + (GRAD_MID.g - GRAD_START.g) * t);
            b = (Uint8)(GRAD_START.b + (GRAD_MID.b - GRAD_START.b) * t);
        } else {
            float t = (charCenter - GRAD_MID_STOP) / (1.0f - GRAD_MID_STOP);
            r = (Uint8)(GRAD_MID.r + (GRAD_END.r - GRAD_MID.r) * t);
            gv = (Uint8)(GRAD_MID.g + (GRAD_END.g - GRAD_MID.g) * t);
            b = (Uint8)(GRAD_MID.b + (GRAD_END.b - GRAD_MID.b) * t);
        }

        SDL_SetTextureColorMod(fa->texture, r, gv, b);
        SDL_SetTextureAlphaMod(fa->texture, alpha);

        float gx = x + g->xoff;
        float gy = y + g->yoff;
        float gw = (float)(g->x1 - g->x0);
        float gh = (float)(g->y1 - g->y0);

        SDL_FRect src = { (float)g->x0, (float)g->y0, gw, gh };
        SDL_FRect dst = { gx, gy, gw, gh };
        SDL_RenderTexture(renderer, fa->texture, &src, &dst);

        x += g->xadvance;
    }
    return x - startX;
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  TEXT LAYOUT — Word wrapping
 *
 *  Breaks text into lines that fit within a given max width. Returns a vector
 *  of (startIndex, length) pairs representing each wrapped line.
 * ══════════════════════════════════════════════════════════════════════════════ */

struct TextLine {
    int start;
    int length;
};

static std::vector<TextLine> wrapText(const FontAtlas* fa, const char* text,
                                      int textLen, float maxWidth)
{
    std::vector<TextLine> lines;
    int lineStart = 0;

    while (lineStart < textLen) {
        /* Skip leading spaces at line start (except first line) */
        if (!lines.empty()) {
            while (lineStart < textLen && text[lineStart] == ' ')
                lineStart++;
        }
        if (lineStart >= textLen) break;

        /* Check for explicit newline */
        int nlPos = -1;
        for (int i = lineStart; i < textLen; i++) {
            if (text[i] == '\n') { nlPos = i; break; }
        }

        /* Find how much fits on one line */
        float x = 0;
        int lastWordEnd = lineStart; /* end of last word that fits */
        int i = lineStart;

        int segEnd = (nlPos >= 0) ? nlPos : textLen;

        while (i < segEnd) {
            /* Scan one word */
            int wordStart = i;
            while (i < segEnd && text[i] != ' ' && text[i] != '\n')
                i++;
            /* Measure word */
            float wordWidth = measureText(fa, text + wordStart, i - wordStart);
            float spaceWidth = 0;
            if (lastWordEnd > lineStart) {
                /* Account for space before this word */
                spaceWidth = measureText(fa, " ", 1);
            }

            if (x + spaceWidth + wordWidth <= maxWidth || lastWordEnd == lineStart) {
                /* Word fits (or it's the first word — must include it) */
                x += spaceWidth + wordWidth;
                lastWordEnd = i;
            } else {
                /* Word doesn't fit — break here */
                break;
            }
            /* Skip spaces between words */
            while (i < segEnd && text[i] == ' ')
                i++;
        }

        int lineLen = lastWordEnd - lineStart;
        if (lineLen <= 0 && nlPos == lineStart) {
            /* Empty line from explicit newline */
            lines.push_back({ lineStart, 0 });
            lineStart = nlPos + 1;
        } else if (lineLen > 0) {
            lines.push_back({ lineStart, lineLen });
            lineStart = lastWordEnd;
            /* If we stopped at a newline, skip it */
            if (nlPos >= 0 && lineStart == nlPos)
                lineStart = nlPos + 1;
        } else {
            break; /* safety: no progress */
        }
    }

    if (lines.empty()) {
        lines.push_back({ 0, 0 });
    }
    return lines;
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  ELEMENT TYPES
 *
 *  Story content is stored as a list of elements. Each element has a type,
 *  position, animation state, and type-specific data.
 * ══════════════════════════════════════════════════════════════════════════════ */

enum ElementType {
    ELEM_NARRATIVE,
    ELEM_DIALOGUE,
    ELEM_CHOICES,
    ELEM_PLAY_AGAIN
};

enum ChoiceState {
    CHOICE_NORMAL,
    CHOICE_HOVERED,
    CHOICE_SELECTED,
    CHOICE_FADING,
    CHOICE_HIDDEN
};

struct ChoiceButton {
    std::string text;
    int originalIndex;    /* Loreline option index */
    bool enabled;
    /* Layout */
    float relY;           /* Y offset relative to element top */
    float width, height;
    /* State */
    ChoiceState state;
    float opacity;
    float slideY;         /* translateY for slide animation */
};

struct Element {
    ElementType type;

    /* Position in content space */
    float y;
    float height;

    /* Fade-in animation */
    double animStartTime;
    float opacity;        /* 0..1 */
    float slideY;         /* translateY offset for fade-in */
    bool animComplete;

    /* NARRATIVE / DIALOGUE data */
    std::string text;
    std::string characterName; /* empty for narrative */
    std::vector<TextLine> wrappedLines;
    std::vector<TextLine> nameLines; /* wrapped name + separator */
    float nameWidth;      /* width of "Name : " prefix */

    /* CHOICES data */
    std::vector<ChoiceButton> buttons;
    bool choiceMade;
    int selectedIndex;
    double selectionTime;
    void (*selectCallback)(int);

    /* PLAY_AGAIN data */
    bool visible;
};


/* ══════════════════════════════════════════════════════════════════════════════
 *  PENDING ACTIONS (timed callbacks)
 *
 *  Used to implement delays between dialogue lines, before choices appear,
 *  and before the play-again button shows. Mirrors the web sample's
 *  setTimeout-based approach.
 * ══════════════════════════════════════════════════════════════════════════════ */

struct PendingAction {
    double fireTime;
    enum ActionType {
        ACTION_ADVANCE,
        ACTION_SELECT,
        ACTION_SHOW_CHOICES,
        ACTION_SHOW_PLAY_AGAIN,
        ACTION_RESTART
    } type;
    /* For ACTION_ADVANCE: the advance() function pointer from Loreline */
    void (*advanceFn)(void);
    /* For ACTION_SHOW_CHOICES: stored choice data */
    std::vector<ChoiceButton> choiceButtons;
    void (*selectFn)(int);
};


/* ══════════════════════════════════════════════════════════════════════════════
 *  APPLICATION STATE
 * ══════════════════════════════════════════════════════════════════════════════ */

struct AppState {
    SDL_Window* window;
    SDL_Renderer* renderer;

    /* Fonts */
    FontAtlas narrativeFont;   /* Literata Italic — for narrative text  */
    FontAtlas uiFont;          /* Outfit Regular — for dialogue & choices */
    FontAtlas uiBoldFont;      /* Outfit SemiBold — for character names   */

    /* Loreline */
    Loreline_Script* script;
    Loreline_Interpreter* interpreter;
    bool storyFinished;

    /* Content */
    std::vector<Element> elements;
    std::vector<PendingAction> pending;

    /* Scroll */
    float scrollOffset;
    float scrollTarget;
    float scrollStart;
    double scrollAnimStart;
    float contentHeight;
    float maxContentHeight;  /* height keeper — only grows */

    /* Timing */
    double currentTime;
    Uint64 lastTick;

    /* Touch input */
    float touchStartX;       /* X position at FINGER_DOWN (pixels) */
    float touchStartY;       /* Y position at FINGER_DOWN (pixels) */
    float touchScrollStart;  /* scrollOffset at FINGER_DOWN */
    bool  isTouchDragging;   /* true once finger moved beyond threshold */

    /* Window */
    int winW, winH;
    float scale;             /* display scale for DPI */

    /* Resource base path */
    std::string basePath;
};

static AppState* g_app = NULL; /* for Loreline callbacks */


/* ══════════════════════════════════════════════════════════════════════════════
 *  SCROLL SYSTEM
 *
 *  Smooth scroll with quadratic ease-in-out, matching the web sample.
 *  Duration scales with distance (250..600ms).
 * ══════════════════════════════════════════════════════════════════════════════ */

static void scrollToBottom(AppState* app) {
    float maxScroll = app->contentHeight - (float)app->winH + PADDING_TOP * app->scale;
    if (maxScroll < 0) maxScroll = 0;
    if (maxScroll <= app->scrollOffset) return;

    app->scrollStart = app->scrollOffset;
    app->scrollTarget = maxScroll;
    app->scrollAnimStart = app->currentTime;
}

static void updateScroll(AppState* app) {
    if (app->scrollAnimStart < 0) return;

    double elapsed = app->currentTime - app->scrollAnimStart;
    float dist = app->scrollTarget - app->scrollStart;
    float duration = 0.4f; /* constant duration — larger distances just scroll faster */

    float t = (float)(elapsed / duration);
    if (t > 1.0f) t = 1.0f;

    /* Quadratic ease-in-out */
    float ease = t < 0.5f ? 2.0f * t * t : -1.0f + (4.0f - 2.0f * t) * t;
    app->scrollOffset = app->scrollStart + dist * ease;

    if (t >= 1.0f) app->scrollAnimStart = -1;
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  CONTENT MANAGEMENT
 * ══════════════════════════════════════════════════════════════════════════════ */

/* On wide mobile screens (landscape), cap content width so there is enough
 * vertical space for text.  The limit is 1.3× the window height. */
static float computeMaxContentWidth(AppState* app) {
    float maxW = CONTENT_MAX_WIDTH * app->scale;
    float heightCap = (float)app->winH * 1.3f;
    return maxW < heightCap ? maxW : heightCap;
}

static float computeContentX(AppState* app) {
    float pad = PADDING_SIDE * app->scale;
    float maxW = computeMaxContentWidth(app);
    float availW = (float)app->winW - pad * 2;
    if (availW > maxW) {
        return ((float)app->winW - maxW) * 0.5f;
    }
    return pad;
}

static float computeContentWidth(AppState* app) {
    float pad = PADDING_SIDE * app->scale;
    float maxW = computeMaxContentWidth(app);
    float availW = (float)app->winW - pad * 2;
    return availW < maxW ? availW : maxW;
}

static void updateContentHeight(AppState* app) {
    float h = PADDING_TOP * app->scale;
    for (size_t i = 0; i < app->elements.size(); i++) {
        h = app->elements[i].y + app->elements[i].height;
    }
    h += (float)app->winH * 0.2f; /* 20vh bottom padding */
    app->contentHeight = h;
    if (h > app->maxContentHeight) app->maxContentHeight = h;
}

/* Name separator: thin space + colon + three-per-em space + hair space
 * In UTF-8: \xe2\x80\x89 : \xe2\x80\x84 \xe2\x80\x8a
 * Since stb_truetype only handles single-byte chars, we simplify to ": " */
static const char* NAME_SEP = ": ";

static void appendElement(AppState* app, Element& el) {
    float y = PADDING_TOP * app->scale;
    if (!app->elements.empty()) {
        Element& last = app->elements.back();
        y = last.y + last.height;
    }
    el.y = y;
    el.animStartTime = app->currentTime;
    el.opacity = 0;
    el.slideY = 4.0f * app->scale;
    el.animComplete = false;

    app->elements.push_back(el);
    updateContentHeight(app);
    scrollToBottom(app);
}

static void appendNarrative(AppState* app, const char* text) {
    float contentW = computeContentWidth(app);
    Element el;
    el.type = ELEM_NARRATIVE;
    el.text = text;
    el.characterName = "";
    el.nameWidth = 0;
    el.choiceMade = false;
    el.selectedIndex = -1;
    el.selectionTime = 0;
    el.selectCallback = NULL;
    el.visible = true;

    el.wrappedLines = wrapText(&app->narrativeFont, text, (int)strlen(text), contentW);
    el.height = (float)el.wrappedLines.size() * app->narrativeFont.lineHeight
                + NARRATIVE_MARGIN * app->scale;

    appendElement(app, el);
}

static void appendDialogue(AppState* app, const char* charName, const char* text) {
    float contentW = computeContentWidth(app);
    Element el;
    el.type = ELEM_DIALOGUE;
    el.text = text;
    el.characterName = charName;
    el.choiceMade = false;
    el.selectedIndex = -1;
    el.selectionTime = 0;
    el.selectCallback = NULL;
    el.visible = true;

    /* Measure the name prefix width: "CharName: " */
    std::string prefix = std::string(charName) + NAME_SEP;
    el.nameWidth = measureText(&app->uiBoldFont, prefix.c_str(), (int)prefix.size());

    /* Wrap the dialogue text, accounting for the name prefix on the first line */
    float firstLineWidth = contentW - el.nameWidth;
    if (firstLineWidth < contentW * 0.3f) firstLineWidth = contentW; /* fallback */

    /* Simple approach: wrap full text to content width */
    el.wrappedLines = wrapText(&app->uiFont, text, (int)strlen(text), contentW);

    /* If the first line is too wide with the name prefix, re-wrap */
    if (!el.wrappedLines.empty()) {
        float firstW = measureText(&app->uiFont, text + el.wrappedLines[0].start,
                                   el.wrappedLines[0].length);
        if (firstW + el.nameWidth > contentW) {
            el.wrappedLines = wrapText(&app->uiFont, text, (int)strlen(text), firstLineWidth);
        }
    }

    el.height = (float)el.wrappedLines.size() * app->uiFont.lineHeight
                + DIALOGUE_MARGIN * app->scale;

    appendElement(app, el);
}

static void showChoices(AppState* app, std::vector<ChoiceButton>& buttons,
                        void (*selectFn)(int))
{
    float contentW = computeContentWidth(app);
    Element el;
    el.type = ELEM_CHOICES;
    el.text = "";
    el.characterName = "";
    el.nameWidth = 0;
    el.choiceMade = false;
    el.selectedIndex = -1;
    el.selectionTime = 0;
    el.selectCallback = selectFn;
    el.visible = true;

    float y = CHOICE_MARGIN_TOP * app->scale;
    float padX = CHOICE_PAD_X * app->scale;
    float padY = CHOICE_PAD_Y * app->scale;
    float gap = CHOICE_GAP * app->scale;

    for (size_t i = 0; i < buttons.size(); i++) {
        ChoiceButton& btn = buttons[i];
        btn.state = CHOICE_NORMAL;
        btn.opacity = 1.0f;
        btn.slideY = 0;

        /* Compute button height based on text wrapping */
        float textW = contentW - padX * 2;
        std::vector<TextLine> lines = wrapText(&app->uiFont, btn.text.c_str(),
                                               (int)btn.text.size(), textW);
        float btnLineH = app->uiFont.fontSize * BTN_LINE_HEIGHT_MULT;
        float textH = (float)lines.size() * btnLineH;
        btn.height = textH + padY * 2;
        btn.width = contentW;

        if (i > 0) y += gap;
        btn.relY = y;
        y += btn.height;
    }

    el.buttons = buttons;
    el.height = y + DIALOGUE_MARGIN * app->scale;

    appendElement(app, el);
}

static void showPlayAgain(AppState* app) {
    Element el;
    el.type = ELEM_PLAY_AGAIN;
    el.text = "Play again";
    el.characterName = "";
    el.nameWidth = 0;
    el.choiceMade = false;
    el.selectedIndex = -1;
    el.selectionTime = 0;
    el.selectCallback = NULL;
    el.visible = false; /* shown after delay */

    float padY = 6.0f * app->scale;
    float padX = 11.0f * app->scale;
    float textH = app->uiFont.lineHeight;
    el.height = PLAYAGAIN_MARGIN * app->scale + textH + padY * 2;

    appendElement(app, el);
}

static void clearContent(AppState* app) {
    app->elements.clear();
    app->pending.clear();
    app->scrollOffset = 0;
    app->scrollTarget = 0;
    app->scrollStart = 0;
    app->scrollAnimStart = -1;
    app->contentHeight = 0;
    app->maxContentHeight = 0;
    app->storyFinished = false;
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  ANIMATION UPDATES
 *
 *  Called each frame to update fade-in and choice selection animations.
 * ══════════════════════════════════════════════════════════════════════════════ */

/* CSS "ease" approximation: cubic-bezier(0.25, 0.1, 0.25, 1.0) */
static float easeOut(float t) {
    /* Simple ease-out approximation */
    return 1.0f - (1.0f - t) * (1.0f - t);
}

static void updateAnimations(AppState* app) {
    for (size_t i = 0; i < app->elements.size(); i++) {
        Element& el = app->elements[i];

        /* Fade-in animation */
        if (!el.animComplete) {
            double t = (app->currentTime - el.animStartTime) / ANIM_FADEIN;
            if (t >= 1.0) {
                t = 1.0;
                el.animComplete = true;
            }
            float e = easeOut((float)t);
            el.opacity = e;
            el.slideY = 4.0f * app->scale * (1.0f - e);
        }

        /* Choice selection animation */
        if (el.type == ELEM_CHOICES && el.choiceMade) {
            double elapsed = app->currentTime - el.selectionTime;

            for (size_t j = 0; j < el.buttons.size(); j++) {
                ChoiceButton& btn = el.buttons[j];
                if ((int)j == el.selectedIndex) {
                    /* Selected button */
                    if (elapsed >= ANIM_CHOICE_P2 && elapsed < ANIM_CHOICE_P3) {
                        /* Phase 2: slide up to top of container */
                        float targetY = el.buttons[0].relY - btn.relY;
                        float pt = (float)((elapsed - ANIM_CHOICE_P2) / (ANIM_CHOICE_P3 - ANIM_CHOICE_P2));
                        if (pt > 1.0f) pt = 1.0f;
                        float ease = pt < 0.5f ? 2.0f * pt * pt
                                               : -1.0f + (4.0f - 2.0f * pt) * pt;
                        btn.slideY = targetY * ease;
                    } else if (elapsed >= ANIM_CHOICE_P3) {
                        /* Phase 3: snap to natural position */
                        btn.slideY = 0;
                        btn.relY = el.buttons[0].relY;
                    }
                } else {
                    /* Other buttons: fade out */
                    if (elapsed < 0.25) {
                        btn.opacity = 1.0f - (float)(elapsed / 0.25);
                    } else {
                        btn.opacity = 0;
                        btn.state = CHOICE_HIDDEN;
                    }
                }
            }

            /* Phase 3: call Loreline callback */
            if (elapsed >= ANIM_CHOICE_P3 && el.selectCallback) {
                void (*fn)(int) = el.selectCallback;
                int idx = el.buttons[el.selectedIndex].originalIndex;
                el.selectCallback = NULL; /* prevent double-call */

                /* Recalculate element height (only selected button visible) */
                ChoiceButton& selBtn = el.buttons[el.selectedIndex];
                el.height = CHOICE_MARGIN_TOP * app->scale + selBtn.height
                            + CHOICE_SEL_MARGIN * app->scale;
                /* Shift subsequent elements */
                for (size_t k = i + 1; k < app->elements.size(); k++) {
                    app->elements[k].y = app->elements[k-1].y + app->elements[k-1].height;
                }
                updateContentHeight(app);

                fn(idx);
            }
        }
    }
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  RENDERING
 * ══════════════════════════════════════════════════════════════════════════════ */

static void renderElement(AppState* app, const Element& el, float contentX,
                          float contentW, float scrollOff)
{
    float baseY = el.y - scrollOff + el.slideY;
    Uint8 alpha = (Uint8)(el.opacity * 255.0f);
    if (alpha == 0) return;

    SDL_Renderer* r = app->renderer;

    if (el.type == ELEM_NARRATIVE) {
        /* Italic serif text, muted color */
        Color col = COL_TEXT_MUTED;
        col.a = alpha;
        float ly = baseY + app->narrativeFont.ascent;
        for (size_t i = 0; i < el.wrappedLines.size(); i++) {
            const TextLine& line = el.wrappedLines[i];
            drawText(r, &app->narrativeFont, contentX, ly,
                     el.text.c_str() + line.start, line.length, col);
            ly += app->narrativeFont.lineHeight;
        }
    }
    else if (el.type == ELEM_DIALOGUE) {
        float ly = baseY + app->uiFont.ascent;
        Color textCol = COL_TEXT;
        textCol.a = alpha;

        /* First line: character name (gradient, bold) + text */
        if (!el.characterName.empty() && !el.wrappedLines.empty()) {
            std::string prefix = el.characterName + NAME_SEP;
            float nameAdv = drawTextGradient(r, &app->uiBoldFont,
                                              contentX, ly,
                                              prefix.c_str(), (int)prefix.size(),
                                              alpha);

            /* Draw first line of dialogue text after the name */
            const TextLine& firstLine = el.wrappedLines[0];
            drawText(r, &app->uiFont, contentX + nameAdv, ly,
                     el.text.c_str() + firstLine.start, firstLine.length, textCol);
            ly += app->uiFont.lineHeight;

            /* Remaining wrapped lines */
            for (size_t i = 1; i < el.wrappedLines.size(); i++) {
                const TextLine& line = el.wrappedLines[i];
                drawText(r, &app->uiFont, contentX, ly,
                         el.text.c_str() + line.start, line.length, textCol);
                ly += app->uiFont.lineHeight;
            }
        }
    }
    else if (el.type == ELEM_CHOICES) {
        float padX = CHOICE_PAD_X * app->scale;
        float padY = CHOICE_PAD_Y * app->scale;

        for (size_t i = 0; i < el.buttons.size(); i++) {
            const ChoiceButton& btn = el.buttons[i];
            if (btn.state == CHOICE_HIDDEN) continue;

            float btnAlpha = el.opacity * btn.opacity;
            if (btnAlpha < 0.01f) continue;
            Uint8 ba = (Uint8)(btnAlpha * 255.0f);

            float bx = contentX;
            float by = baseY + btn.relY + btn.slideY;
            float bw = btn.width;
            float bh = btn.height;

            /* Button background (subtle glow on hover/selected) */
            if (btn.state == CHOICE_HOVERED || btn.state == CHOICE_SELECTED) {
                SDL_SetRenderDrawColor(r, COL_GLOW.r, COL_GLOW.g, COL_GLOW.b,
                                       (Uint8)(COL_GLOW.a * btnAlpha));
                SDL_FRect bgRect = { bx, by, bw, bh };
                SDL_RenderFillRect(r, &bgRect);
            }

            /* Button border */
            Color borderCol = (btn.state == CHOICE_HOVERED || btn.state == CHOICE_SELECTED)
                              ? COL_PURPLE : COL_BORDER;
            SDL_SetRenderDrawColor(r, borderCol.r, borderCol.g, borderCol.b,
                                   (Uint8)(borderCol.a * btnAlpha / 255));
            SDL_FRect borderRect = { bx, by, bw, bh };
            SDL_RenderRect(r, &borderRect);

            /* Button text */
            Color btnTextCol = (btn.state == CHOICE_HOVERED || btn.state == CHOICE_SELECTED)
                               ? COL_TEXT : COL_TEXT_MUTED;
            btnTextCol.a = ba;

            float textW = bw - padX * 2;
            std::vector<TextLine> lines = wrapText(&app->uiFont, btn.text.c_str(),
                                                   (int)btn.text.size(), textW);
            float btnLineH = app->uiFont.fontSize * BTN_LINE_HEIGHT_MULT;
            float ty = by + padY + app->uiFont.ascent + BTN_TEXT_OFFSET_Y * app->scale;
            for (size_t li = 0; li < lines.size(); li++) {
                drawText(r, &app->uiFont, bx + padX, ty,
                         btn.text.c_str() + lines[li].start, lines[li].length,
                         btnTextCol);
                ty += btnLineH;
            }
        }
    }
    else if (el.type == ELEM_PLAY_AGAIN && el.visible) {
        float padX = 11.0f * app->scale;
        float padY = 6.0f * app->scale;
        float btnW = measureText(&app->uiFont, el.text.c_str(), (int)el.text.size())
                     + padX * 2;
        float btnH = app->uiFont.lineHeight + padY * 2;
        float bx = contentX;
        float by = baseY + PLAYAGAIN_MARGIN * app->scale;

        /* Border */
        Color borderCol = COL_BORDER;
        borderCol.a = alpha;
        SDL_SetRenderDrawColor(r, borderCol.r, borderCol.g, borderCol.b, alpha);
        SDL_FRect borderRect = { bx, by, btnW, btnH };
        SDL_RenderRect(r, &borderRect);

        /* Text */
        Color dimCol = COL_TEXT_DIM;
        dimCol.a = alpha;
        drawText(r, &app->uiFont, bx + padX, by + padY + app->uiFont.ascent + BTN_TEXT_OFFSET_Y * app->scale,
                 el.text.c_str(), (int)el.text.size(), dimCol);
    }
}

static void render(AppState* app) {
    SDL_Renderer* r = app->renderer;

    /* Clear background */
    SDL_SetRenderDrawColor(r, COL_BG.r, COL_BG.g, COL_BG.b, 0xff);
    SDL_RenderClear(r);

    float contentX = computeContentX(app);
    float contentW = computeContentWidth(app);

    /* Use the height keeper to prevent scroll jumps */
    float scrollOff = app->scrollOffset;

    /* Render visible elements */
    for (size_t i = 0; i < app->elements.size(); i++) {
        const Element& el = app->elements[i];
        float top = el.y - scrollOff + el.slideY;
        float bottom = top + el.height;

        /* Cull elements outside viewport */
        if (bottom < -50 || top > app->winH + 50) continue;

        renderElement(app, el, contentX, contentW, scrollOff);
    }

    SDL_RenderPresent(r);
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  RESOURCE LOADING
 *
 *  Uses SDL_IOFromFile for cross-platform asset access.
 *  On Android, this reads from the APK's assets/ directory.
 *  On iOS, SDL_GetBasePath() returns the app bundle path.
 * ══════════════════════════════════════════════════════════════════════════════ */

static std::string readFileStr(const char* relativePath, const std::string& basePath) {
    std::string fullPath;
#if defined(__ANDROID__)
    fullPath = relativePath; /* SDL handles Android asset paths */
#else
    fullPath = basePath + relativePath;
#endif

    SDL_IOStream* io = SDL_IOFromFile(fullPath.c_str(), "rb");
    if (!io) return std::string();

    Sint64 size = SDL_GetIOSize(io);
    if (size <= 0) { SDL_CloseIO(io); return std::string(); }

    std::string content((size_t)size, '\0');
    SDL_ReadIO(io, &content[0], (size_t)size);
    SDL_CloseIO(io);
    return content;
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  LORELINE INTEGRATION
 *
 *  Callbacks that bridge Loreline events to the visual element system.
 *  Each callback creates UI elements and schedules delayed actions.
 * ══════════════════════════════════════════════════════════════════════════════ */

static void onFileRequest(Loreline_String filePath,
                          void (*provide)(Loreline_String content),
                          void* /* userData */)
{
    std::string content = readFileStr(filePath.c_str(), g_app->basePath);
    if (content.empty()) {
        provide(Loreline_String());
    } else {
        provide(Loreline_String(content.c_str()));
    }
}

static void onDialogue(Loreline_Interpreter* interp,
                       Loreline_String character,
                       Loreline_String text,
                       const Loreline_TextTag* /* tags */,
                       int /* tagCount */,
                       void (*advance)(void),
                       void* /* userData */)
{
    AppState* app = g_app;

    if (!character.isNull()) {
        /* Dialogue — resolve display name */
        Loreline_Value nameVal = Loreline_getCharacterField(interp, character, "name");
        const char* displayName = (nameVal.type == Loreline_StringValue && nameVal.stringValue)
            ? nameVal.stringValue.c_str()
            : character.c_str();
        appendDialogue(app, displayName, text.c_str());
    } else {
        /* Narrative text */
        appendNarrative(app, text.c_str());
    }

    /* Schedule advance after delay */
    PendingAction action;
    action.fireTime = app->currentTime + DELAY_DIALOGUE;
    action.type = PendingAction::ACTION_ADVANCE;
    action.advanceFn = advance;
    action.selectFn = NULL;
    app->pending.push_back(action);
}

static void onChoice(Loreline_Interpreter* /* interp */,
                     const Loreline_ChoiceOption* options,
                     int optionCount,
                     void (*select)(int index),
                     void* /* userData */)
{
    AppState* app = g_app;

    /* Copy options (data may not persist after this call returns) */
    std::vector<ChoiceButton> buttons;
    for (int i = 0; i < optionCount; i++) {
        if (!options[i].enabled) continue;
        ChoiceButton btn;
        btn.text = options[i].text.c_str();
        btn.originalIndex = i;
        btn.enabled = options[i].enabled;
        btn.relY = 0;
        btn.width = 0;
        btn.height = 0;
        btn.state = CHOICE_NORMAL;
        btn.opacity = 1.0f;
        btn.slideY = 0;
        buttons.push_back(btn);
    }

    /* Schedule showing choices after delay */
    PendingAction action;
    action.fireTime = app->currentTime + DELAY_CHOICES;
    action.type = PendingAction::ACTION_SHOW_CHOICES;
    action.advanceFn = NULL;
    action.choiceButtons = buttons;
    action.selectFn = select;
    app->pending.push_back(action);
}

static void onFinish(Loreline_Interpreter* /* interp */,
                     void* /* userData */)
{
    AppState* app = g_app;
    app->storyFinished = true;

    /* Schedule showing play-again button after delay */
    PendingAction action;
    action.fireTime = app->currentTime + DELAY_PLAY_AGAIN;
    action.type = PendingAction::ACTION_SHOW_PLAY_AGAIN;
    action.advanceFn = NULL;
    action.selectFn = NULL;
    app->pending.push_back(action);
}

static void startStory(AppState* app);

static void processPendingActions(AppState* app) {
    size_t i = 0;
    while (i < app->pending.size()) {
        if (app->currentTime >= app->pending[i].fireTime) {
            PendingAction action = app->pending[i];
            app->pending.erase(app->pending.begin() + i);

            switch (action.type) {
            case PendingAction::ACTION_ADVANCE:
                if (action.advanceFn) action.advanceFn();
                break;
            case PendingAction::ACTION_SHOW_CHOICES:
                showChoices(app, action.choiceButtons, action.selectFn);
                break;
            case PendingAction::ACTION_SHOW_PLAY_AGAIN:
                showPlayAgain(app);
                /* Make it visible with a fade-in after the element is created */
                if (!app->elements.empty()) {
                    Element& el = app->elements.back();
                    el.visible = true;
                }
                break;
            case PendingAction::ACTION_RESTART:
                startStory(app);
                break;
            default:
                break;
            }
        } else {
            i++;
        }
    }
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  STORY LIFECYCLE
 * ══════════════════════════════════════════════════════════════════════════════ */

static void startStory(AppState* app) {
    /* Clean up previous interpreter */
    if (app->interpreter) {
        Loreline_releaseInterpreter(app->interpreter);
        app->interpreter = NULL;
    }

    clearContent(app);

    if (!app->script) {
        appendNarrative(app, "Error: no story loaded.");
        return;
    }

    app->interpreter = Loreline_play(
        app->script, onDialogue, onChoice, onFinish
    );
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  INPUT HANDLING
 * ══════════════════════════════════════════════════════════════════════════════ */

static void handleClick(AppState* app, float mx, float my) {
    float contentX = computeContentX(app);
    float contentW = computeContentWidth(app);
    float scrollOff = app->scrollOffset;

    for (size_t i = 0; i < app->elements.size(); i++) {
        Element& el = app->elements[i];

        if (el.type == ELEM_CHOICES && !el.choiceMade) {
            float baseY = el.y - scrollOff + el.slideY;

            for (size_t j = 0; j < el.buttons.size(); j++) {
                ChoiceButton& btn = el.buttons[j];
                if (btn.state == CHOICE_HIDDEN || btn.state == CHOICE_FADING) continue;

                float bx = contentX;
                float by = baseY + btn.relY;
                float bw = btn.width;
                float bh = btn.height;

                if (mx >= bx && mx <= bx + bw && my >= by && my <= by + bh) {
                    /* Select this choice */
                    el.choiceMade = true;
                    el.selectedIndex = (int)j;
                    el.selectionTime = app->currentTime;

                    btn.state = CHOICE_SELECTED;
                    /* Mark others as fading */
                    for (size_t k = 0; k < el.buttons.size(); k++) {
                        if (k != j) el.buttons[k].state = CHOICE_FADING;
                    }
                    return;
                }
            }
        }
        else if (el.type == ELEM_PLAY_AGAIN && el.visible) {
            float padX = 11.0f * app->scale;
            float padY = 6.0f * app->scale;
            float btnW = measureText(&app->uiFont, el.text.c_str(), (int)el.text.size())
                         + padX * 2;
            float btnH = app->uiFont.lineHeight + padY * 2;
            float bx = contentX;
            float by = el.y - scrollOff + el.slideY + PLAYAGAIN_MARGIN * app->scale;

            if (mx >= bx && mx <= bx + btnW && my >= by && my <= by + btnH) {
                startStory(app);
                return;
            }
        }
    }
}

static void handleHover(AppState* app, float mx, float my) {
    float contentX = computeContentX(app);
    float scrollOff = app->scrollOffset;

    for (size_t i = 0; i < app->elements.size(); i++) {
        Element& el = app->elements[i];
        if (el.type != ELEM_CHOICES || el.choiceMade) continue;

        float baseY = el.y - scrollOff + el.slideY;

        for (size_t j = 0; j < el.buttons.size(); j++) {
            ChoiceButton& btn = el.buttons[j];
            if (btn.state == CHOICE_HIDDEN || btn.state == CHOICE_FADING) continue;

            float bx = contentX;
            float by = baseY + btn.relY;
            float bw = btn.width;
            float bh = btn.height;

            if (mx >= bx && mx <= bx + bw && my >= by && my <= by + bh) {
                btn.state = CHOICE_HOVERED;
            } else if (btn.state == CHOICE_HOVERED) {
                btn.state = CHOICE_NORMAL;
            }
        }
    }
}


/* ══════════════════════════════════════════════════════════════════════════════
 *  SDL3 APP CALLBACKS
 *
 *  Modern SDL3 entry point. SDL handles platform-specific lifecycle (iOS
 *  UIKit, Android Activity, desktop main loop) and calls these four functions.
 * ══════════════════════════════════════════════════════════════════════════════ */

SDL_AppResult SDL_AppInit(void** appstate, int argc, char* argv[])
{
    AppState* app = new AppState();
    *appstate = app;
    g_app = app;

    /* Initialize SDL */
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    /* Prevent SDL from synthesizing mouse events from touch input —
     * we handle finger events directly for proper tap-vs-scroll. */
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");

    /* Lock to landscape on mobile (SDLActivity overrides the manifest). */
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");

    /* Create window */
    app->window = SDL_CreateWindow("Loreline — SDL3 Sample",
                                   960, 640,
                                   SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
    if (!app->window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    /* Create renderer */
    app->renderer = SDL_CreateRenderer(app->window, NULL);
    if (!app->renderer) {
        SDL_Log("SDL_CreateRenderer failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    /* Get renderer output dimensions (pixels) and DPI scale.
     * We use renderer output size (not window size) because with
     * SDL_WINDOW_HIGH_PIXEL_DENSITY the renderer works in pixel coords
     * while SDL_GetWindowSize returns points. */
    SDL_GetRenderOutputSize(app->renderer, &app->winW, &app->winH);
    app->scale = SDL_GetWindowDisplayScale(app->window);
    if (app->scale < 1.0f) app->scale = 1.0f;

    /* Determine base path for resources */
    const char* base = SDL_GetBasePath();
    if (base) {
        app->basePath = base;
    }
#if defined(__ANDROID__)
    app->basePath = ""; /* SDL_IOFromFile handles Android assets */
#endif

    /* Load fonts */
    float fontScale = app->scale;
    std::string fontsDir = app->basePath + "fonts/";

    if (!loadFontAtlas(&app->narrativeFont, app->renderer,
                       (fontsDir + "Literata-Italic.ttf").c_str(),
                       FONT_SIZE_NARRATIVE * fontScale)) {
        SDL_Log("Failed to load narrative font");
        return SDL_APP_FAILURE;
    }
    if (!loadFontAtlas(&app->uiFont, app->renderer,
                       (fontsDir + "Outfit-Regular.ttf").c_str(),
                       FONT_SIZE_TEXT * fontScale)) {
        SDL_Log("Failed to load UI font");
        return SDL_APP_FAILURE;
    }
    if (!loadFontAtlas(&app->uiBoldFont, app->renderer,
                       (fontsDir + "Outfit-SemiBold.ttf").c_str(),
                       FONT_SIZE_TEXT * fontScale)) {
        SDL_Log("Failed to load UI bold font");
        return SDL_APP_FAILURE;
    }

    /* Initialize Loreline */
    Loreline_init();

    /* Load and parse the story */
    std::string storyFile = "story/CoffeeShop.lor";
    if (argc >= 2) storyFile = argv[1];

    std::string content = readFileStr(storyFile.c_str(), app->basePath);
    if (content.empty()) {
        SDL_Log("Failed to read story file: %s", storyFile.c_str());
        return SDL_APP_FAILURE;
    }

    app->script = Loreline_parse(
        content.c_str(), storyFile.c_str(), onFileRequest, NULL
    );
    if (!app->script) {
        SDL_Log("Failed to parse story");
        return SDL_APP_FAILURE;
    }

    /* Initialize state */
    app->interpreter = NULL;
    app->storyFinished = false;
    app->scrollOffset = 0;
    app->scrollTarget = 0;
    app->scrollStart = 0;
    app->scrollAnimStart = -1;
    app->contentHeight = 0;
    app->maxContentHeight = 0;
    app->lastTick = SDL_GetPerformanceCounter();
    app->currentTime = 0;

    /* Start playing */
    startStory(app);

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void* appstate)
{
    AppState* app = (AppState*)appstate;

    /* Update timing */
    Uint64 now = SDL_GetPerformanceCounter();
    Uint64 freq = SDL_GetPerformanceFrequency();
    double delta = (double)(now - app->lastTick) / (double)freq;
    app->lastTick = now;
    app->currentTime += delta;

    /* Process pending timed actions */
    processPendingActions(app);

    /* Update Loreline (flushes pending callbacks) */
    Loreline_update(delta);

    /* Update animations */
    updateAnimations(app);
    updateScroll(app);

    /* Render */
    render(app);

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event* event)
{
    AppState* app = (AppState*)appstate;

    switch (event->type) {
    case SDL_EVENT_QUIT:
        return SDL_APP_SUCCESS;

    case SDL_EVENT_KEY_DOWN:
        if (event->key.key == SDLK_ESCAPE)
            return SDL_APP_SUCCESS;
        break;

    case SDL_EVENT_MOUSE_BUTTON_DOWN:
        if (event->button.button == SDL_BUTTON_LEFT) {
            handleClick(app, event->button.x * app->scale,
                        event->button.y * app->scale);
        }
        break;

    case SDL_EVENT_MOUSE_MOTION:
        handleHover(app, event->motion.x * app->scale,
                    event->motion.y * app->scale);
        break;

    case SDL_EVENT_MOUSE_WHEEL: {
        float scrollAmount = event->wheel.y * 40.0f * app->scale;
        app->scrollOffset -= scrollAmount;
        /* Clamp scroll */
        if (app->scrollOffset < 0) app->scrollOffset = 0;
        float maxScroll = app->maxContentHeight - (float)app->winH;
        if (maxScroll < 0) maxScroll = 0;
        if (app->scrollOffset > maxScroll) app->scrollOffset = maxScroll;
        /* Cancel any animated scroll */
        app->scrollAnimStart = -1;
        break;
    }

    case SDL_EVENT_FINGER_DOWN: {
        float fx = event->tfinger.x * (float)app->winW;
        float fy = event->tfinger.y * (float)app->winH;
        app->touchStartX = fx;
        app->touchStartY = fy;
        app->touchScrollStart = app->scrollOffset;
        app->isTouchDragging = false;
        /* Cancel any animated scroll */
        app->scrollAnimStart = -1;
        break;
    }

    case SDL_EVENT_FINGER_MOTION: {
        float fy = event->tfinger.y * (float)app->winH;
        float dy = fy - app->touchStartY;
        float dragThreshold = 10.0f * app->scale;
        if (!app->isTouchDragging && (dy > dragThreshold || dy < -dragThreshold)) {
            app->isTouchDragging = true;
        }
        if (app->isTouchDragging) {
            app->scrollOffset = app->touchScrollStart - dy;
            /* Clamp scroll */
            if (app->scrollOffset < 0) app->scrollOffset = 0;
            float maxScroll = app->maxContentHeight - (float)app->winH;
            if (maxScroll < 0) maxScroll = 0;
            if (app->scrollOffset > maxScroll) app->scrollOffset = maxScroll;
        }
        break;
    }

    case SDL_EVENT_FINGER_UP: {
        if (!app->isTouchDragging) {
            /* Short tap — treat as click */
            float fx = event->tfinger.x * (float)app->winW;
            float fy = event->tfinger.y * (float)app->winH;
            handleClick(app, fx, fy);
        }
        app->isTouchDragging = false;
        break;
    }

    case SDL_EVENT_WINDOW_RESIZED:
        SDL_GetRenderOutputSize(app->renderer, &app->winW, &app->winH);
        app->scale = SDL_GetWindowDisplayScale(app->window);
        if (app->scale < 1.0f) app->scale = 1.0f;
        /* TODO: relayout text and recreate font atlases for new DPI */
        break;

    default:
        break;
    }

    return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate, SDL_AppResult /* result */)
{
    AppState* app = (AppState*)appstate;
    if (!app) return;

    /* Cleanup Loreline */
    if (app->interpreter) Loreline_releaseInterpreter(app->interpreter);
    if (app->script) Loreline_releaseScript(app->script);
    Loreline_dispose();

    /* Cleanup fonts */
    freeFontAtlas(&app->narrativeFont);
    freeFontAtlas(&app->uiFont);
    freeFontAtlas(&app->uiBoldFont);

    /* Cleanup SDL */
    if (app->renderer) SDL_DestroyRenderer(app->renderer);
    if (app->window) SDL_DestroyWindow(app->window);
    SDL_Quit();

    delete app;
}
