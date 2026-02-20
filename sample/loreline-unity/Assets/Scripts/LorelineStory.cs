using UnityEngine;
using UnityEngine.UIElements;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Loreline;

/// <summary>
/// Self-contained Loreline story player for Unity using UI Toolkit.
/// Creates all UI programmatically — just add this to an empty GameObject and press Play.
/// Runs the CoffeeShop.lor sample story.
/// </summary>
public class LorelineStory : MonoBehaviour
{
    // UI Toolkit references
    private UIDocument uiDocument;
    private StyleSheet stylesheet;
    private ScrollView scrollView;
    private VisualElement contentColumn;
    private VisualElement heightKeeper;

    // Timer management — tracked for cancellation on restart
    private List<IVisualElementScheduledItem> pendingTimers = new List<IVisualElementScheduledItem>();

    // Scroll animation state
    private Coroutine scrollCoroutine;

    void Awake()
    {
        SetupUIDocument();
    }

    void Start()
    {
        BuildUI();
        StartStory();
    }

    // ── UI Setup ──────────────────────────────────────────────────────────────

    void SetupUIDocument()
    {
        // Create PanelSettings programmatically
        var panelSettings = ScriptableObject.CreateInstance<PanelSettings>();
        panelSettings.scaleMode = PanelScaleMode.ScaleWithScreenSize;
        panelSettings.referenceResolution = new Vector2Int(1920, 1080);
        panelSettings.screenMatchMode = PanelScreenMatchMode.MatchWidthOrHeight;
        panelSettings.match = 0.5f;

        // Assign a ThemeStyleSheet to suppress "No Theme Style Sheet" warning
        // (our USS provides all styling, so an empty theme is fine)
        panelSettings.themeStyleSheet = ScriptableObject.CreateInstance<ThemeStyleSheet>();

        // Add UIDocument component
        uiDocument = gameObject.AddComponent<UIDocument>();
        uiDocument.panelSettings = panelSettings;

        // Load stylesheet once (applied in BuildUI)
        stylesheet = Resources.Load<StyleSheet>("LorelineStory");
        if (stylesheet == null)
        {
            Debug.LogWarning("Could not load LorelineStory.uss from Resources.");
        }
    }

    void BuildUI()
    {
        var root = uiDocument.rootVisualElement;
        root.Clear();

        // Apply stylesheet (only once — Clear() doesn't remove stylesheets)
        if (stylesheet != null && !root.styleSheets.Contains(stylesheet))
        {
            root.styleSheets.Add(stylesheet);
        }

        root.AddToClassList("root");

        // ScrollView — vertical, full screen
        scrollView = new ScrollView(ScrollViewMode.Vertical);
        scrollView.AddToClassList("scroll-view");
        scrollView.horizontalScrollerVisibility = ScrollerVisibility.Hidden;
        root.Add(scrollView);

        // Two-column wrapper (scroll-stable layout)
        var contentWrapper = new VisualElement();
        contentWrapper.AddToClassList("content-wrapper");
        scrollView.Add(contentWrapper);

        // Content column — story elements go here
        contentColumn = new VisualElement();
        contentColumn.AddToClassList("content-column");
        contentWrapper.Add(contentColumn);

        // Keeper column — zero width, height only grows (prevents scroll jumps)
        var keeperColumn = new VisualElement();
        keeperColumn.AddToClassList("keeper-column");
        contentWrapper.Add(keeperColumn);

        heightKeeper = new VisualElement();
        keeperColumn.Add(heightKeeper);
    }

    // ── Story Loading ─────────────────────────────────────────────────────────

    void StartStory()
    {
        // Cancel all pending timers and coroutines
        ClearTimers();
        StopAllCoroutines();
        scrollCoroutine = null;

        // Clear content
        contentColumn.Clear();
        heightKeeper.style.height = 0;

        // Load and play story
        TextAsset mainAsset = Resources.Load<TextAsset>("CoffeeShop.lor");
        if (mainAsset == null)
        {
            Debug.LogError("Could not load CoffeeShop.lor.txt from Resources!");
            return;
        }

        Script script = Engine.Parse(mainAsset.text, "CoffeeShop.lor", HandleFile);
        if (script != null)
        {
            Engine.Play(script, OnDialogue, OnChoice, OnFinish);
        }
    }

    void HandleFile(string path, Engine.ImportsFileCallback callback)
    {
        string name = Path.GetFileNameWithoutExtension(path) + ".lor";
        TextAsset asset = Resources.Load<TextAsset>(name);
        callback(asset != null ? asset.text : null);
    }

    // ── Story Handlers ────────────────────────────────────────────────────────

    void OnDialogue(Interpreter.Dialogue dialogue)
    {
        string character = dialogue.Character;
        if (character != null)
        {
            string displayName = (string)dialogue.Interpreter.GetCharacterField(character, "name");
            if (displayName != null) character = displayName;
        }

        AppendDialogue(character, dialogue.Text);

        // Auto-advance after 600ms (matching web sample)
        ScheduleDelayed(600, () => dialogue.Callback());
    }

    void OnChoice(Interpreter.Choice choice)
    {
        // Show choices after 500ms delay (matching web sample)
        ScheduleDelayed(500, () =>
        {
            ShowChoices(choice.Options, idx => choice.Callback(idx));
        });
    }

    void OnFinish(Interpreter.Finish finish)
    {
        ShowFinished();
    }

    // ── Rendering: Dialogue & Narrative ───────────────────────────────────────

    void AppendDialogue(string character, string text)
    {
        Label line;

        if (character != null)
        {
            // Dialogue line: char name (bold purple) + text, using rich text
            // Unicode separators match the web sample: thin space + colon + three-per-em space + hair space
            line = new Label();
            line.enableRichText = true;
            line.text = "<b>" + GradientRichText(character + "\u2009:\u2004\u200a") + "</b>" + EscapeRichText(text);
            line.AddToClassList("dialogue");
        }
        else
        {
            // Narrative line: italic serif, muted color
            line = new Label(text);
            line.AddToClassList("narrative");
        }

        contentColumn.Add(line);
        FadeIn(line);
        UpdateHeightKeeper();
        ScrollToBottom();
    }

    // ── Rendering: Choices ────────────────────────────────────────────────────

    void ShowChoices(Interpreter.ChoiceOption[] options, System.Action<int> choiceCallback)
    {
        var choiceContainer = new VisualElement();
        choiceContainer.AddToClassList("choices-container");

        var buttons = new List<Button>();
        bool isFirst = true;
        bool selected = false;

        for (int i = 0; i < options.Length; i++)
        {
            var opt = options[i];
            if (!opt.Enabled) continue;

            int idx = i;
            var btn = new Button();
            btn.text = opt.Text;
            btn.AddToClassList("choice-button");

            // First enabled button: no top margin (USS doesn't support :first-child)
            if (isFirst)
            {
                btn.style.marginTop = 0;
                isFirst = false;
            }

            btn.clicked += () =>
            {
                // Prevent double-clicks during animation
                if (selected) return;
                selected = true;

                // Phase 1: highlight selected, fade others
                foreach (var b in buttons)
                {
                    if (b == btn)
                        b.AddToClassList("selected");
                    else
                        b.AddToClassList("fading");
                }

                // Phase 2 (300ms): slide selected button to top of container
                ScheduleDelayed(300, () =>
                {
                    float btnTop = btn.worldBound.y;
                    float containerTop = choiceContainer.worldBound.y;
                    float offset = btnTop - containerTop;
                    if (offset > 0)
                    {
                        btn.style.translate = new Translate(0, -offset);
                    }
                });

                // Phase 3 (700ms): finalize layout and continue story
                ScheduleDelayed(700, () =>
                {
                    // Hide faded buttons
                    foreach (var b in buttons)
                    {
                        if (b != btn)
                            b.style.display = DisplayStyle.None;
                    }

                    // Disable transitions before resetting position
                    btn.style.transitionDuration = new List<TimeValue> { new TimeValue(0) };
                    btn.style.translate = new Translate(0, 0);
                    btn.style.marginTop = 0;

                    // Re-enable transitions on the next frame
                    btn.schedule.Execute(() =>
                    {
                        btn.style.transitionDuration = StyleKeyword.Null;
                        btn.style.transitionProperty = StyleKeyword.Null;
                    });

                    UpdateHeightKeeper();
                    choiceCallback(idx);
                });
            };

            buttons.Add(btn);
            choiceContainer.Add(btn);
        }

        contentColumn.Add(choiceContainer);
        FadeIn(choiceContainer);
        UpdateHeightKeeper();
        ScrollToBottom();
    }

    // ── Rendering: Story Finished ─────────────────────────────────────────────

    void ShowFinished()
    {
        var resetBtn = new Button();
        resetBtn.text = "Play again";
        resetBtn.AddToClassList("reset-button");
        contentColumn.Add(resetBtn);

        // Initially hidden, then fade in after 500ms
        resetBtn.style.display = DisplayStyle.None;

        ScheduleDelayed(500, () =>
        {
            resetBtn.style.display = DisplayStyle.Flex;
            FadeIn(resetBtn);
            ScrollToBottom();
        });

        resetBtn.clicked += () =>
        {
            BuildUI();
            StartStory();
        };
    }

    // ── Animation Helpers ─────────────────────────────────────────────────────

    /// <summary>
    /// Fades in an element with a subtle upward slide, using USS transition classes.
    /// </summary>
    void FadeIn(VisualElement el)
    {
        el.AddToClassList("fade-in-ready");

        // Next frame: trigger transition by swapping to active class
        el.schedule.Execute(() =>
        {
            el.AddToClassList("fade-in-active");
            el.RemoveFromClassList("fade-in-ready");
        });
    }

    /// <summary>
    /// Updates the height keeper to the current content height.
    /// The keeper's height only ever increases — this prevents scroll jumps
    /// when choice buttons are hidden after selection.
    /// </summary>
    void UpdateHeightKeeper()
    {
        contentColumn.schedule.Execute(() =>
        {
            float h = contentColumn.resolvedStyle.height;
            float currentHeight = heightKeeper.resolvedStyle.height;
            if (float.IsNaN(currentHeight)) currentHeight = 0;
            if (h > currentHeight)
            {
                heightKeeper.style.height = h;
            }
        });
    }

    /// <summary>
    /// Smoothly scrolls the output to the bottom using a coroutine
    /// with quadratic ease-in-out (matching the web sample).
    /// </summary>
    void ScrollToBottom()
    {
        if (scrollCoroutine != null)
            StopCoroutine(scrollCoroutine);
        scrollCoroutine = StartCoroutine(SmoothScrollToBottom());
    }

    IEnumerator SmoothScrollToBottom()
    {
        // Wait for layout to resolve after content changes
        yield return null;
        yield return null;
        yield return null;

        float start = scrollView.verticalScroller.value;
        float target = scrollView.verticalScroller.highValue;

        if (target <= start + 1f)
        {
            scrollCoroutine = null;
            yield break;
        }

        float dist = target - start;
        float duration = Mathf.Min(0.6f, Mathf.Max(0.25f, dist * 0.0012f));
        float elapsed = 0f;

        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = Mathf.Clamp01(elapsed / duration);

            // Quadratic ease-in-out (matching web sample)
            float ease = t < 0.5f ? 2f * t * t : -1f + (4f - 2f * t) * t;

            scrollView.verticalScroller.value = start + dist * ease;
            yield return null;
        }

        scrollView.verticalScroller.value = target;
        scrollCoroutine = null;
    }

    // ── Timer Management ──────────────────────────────────────────────────────

    /// <summary>
    /// Schedules an action after a delay (in milliseconds).
    /// All scheduled items are tracked for cancellation on restart.
    /// </summary>
    void ScheduleDelayed(long delayMs, System.Action action)
    {
        var item = uiDocument.rootVisualElement.schedule.Execute(() => action());
        item.ExecuteLater(delayMs);
        pendingTimers.Add(item);
    }

    /// <summary>
    /// Cancels all pending scheduled actions.
    /// Called when restarting the story to prevent orphaned callbacks.
    /// </summary>
    void ClearTimers()
    {
        foreach (var timer in pendingTimers)
        {
            if (timer != null) timer.Pause();
        }
        pendingTimers.Clear();
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Wraps each visible character in a color tag that interpolates along a gradient,
    /// approximating the web sample's linear-gradient(135deg, #ff5eab 0%, #8b5cf6 40%, #56a0f6 100%).
    /// The 135° diagonal angle means the visible horizontal range is narrower than 0–100%,
    /// so we map characters to the 0.15–0.85 range of the original gradient for a softer look.
    /// </summary>
    static string GradientRichText(string text)
    {
        if (string.IsNullOrEmpty(text)) return "";

        // Gradient stops: #ff5eab at 0%, #8b5cf6 at 40%, #56a0f6 at 100%
        // R, G, B for each stop
        float r0 = 255, g0 = 94,  b0 = 171;  // #ff5eab
        float r1 = 139, g1 = 92,  b1 = 246;  // #8b5cf6
        float r2 = 86,  g2 = 160, b2 = 246;  // #56a0f6

        // Narrower range to approximate the 135° diagonal effect
        const float tMin = 0.30f;
        const float tMax = 0.70f;

        var sb = new System.Text.StringBuilder();
        int len = text.Length;

        for (int i = 0; i < len; i++)
        {
            // Map character position to the narrower gradient range
            float t = len > 1 ? tMin + (tMax - tMin) * i / (len - 1) : 0.4f;

            // Interpolate between stops: 0→0.4 is stop0→stop1, 0.4→1.0 is stop1→stop2
            float r, g, b;
            if (t <= 0.4f)
            {
                float s = t / 0.4f;
                r = r0 + (r1 - r0) * s;
                g = g0 + (g1 - g0) * s;
                b = b0 + (b1 - b0) * s;
            }
            else
            {
                float s = (t - 0.4f) / 0.6f;
                r = r1 + (r2 - r1) * s;
                g = g1 + (g2 - g1) * s;
                b = b1 + (b2 - b1) * s;
            }

            string hex = string.Format("#{0:X2}{1:X2}{2:X2}",
                Mathf.RoundToInt(r), Mathf.RoundToInt(g), Mathf.RoundToInt(b));

            sb.Append("<color=").Append(hex).Append('>').Append(text[i]).Append("</color>");
        }

        return sb.ToString();
    }

    /// <summary>
    /// Wraps text in noparse tags to prevent rich text injection.
    /// </summary>
    static string EscapeRichText(string text)
    {
        if (text == null) return "";
        return "<noparse>" + text + "</noparse>";
    }
}
