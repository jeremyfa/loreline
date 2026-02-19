using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Loreline;

/// <summary>
/// Self-contained Loreline story player for Unity.
/// Creates all UI programmatically — just add this to an empty GameObject and press Play.
/// Runs the CoffeeShop.lor sample story.
/// </summary>
public class LorelineStory : MonoBehaviour
{
    // UI references (created in Awake)
    private ScrollRect scrollRect;
    private RectTransform content;
    private GameObject bottomPanel;
    private Button restartButton;
    private List<GameObject> choiceButtons = new List<GameObject>();

    // Dark theme colors
    private static readonly Color ContentBg = HexColor("16162a");
    private static readonly Color TextColor = HexColor("e0e0e0");
    private static readonly Color NarratorColor = HexColor("9a9ab0");
    private static readonly Color ChoiceBg = HexColor("252540");
    private static readonly Color ChoiceText = HexColor("d0d0e0");
    private static readonly Color ChoiceTextDimmed = HexColor("808098");
    private static readonly Color BottomBarBg = new Color(0.08f, 0.08f, 0.15f, 0.9f);
    private static readonly Color AccentColor = HexColor("8080a0");

    private static readonly Dictionary<string, string> CharacterColors = new Dictionary<string, string>
    {
        { "Barista", "#c9956a" },
        { "Dr. Bean", "#ff6b6b" },
        { "Sarah", "#6bc5cd" },
        { "James", "#6bcd7b" },
        { "Player", "#b07de8" }
    };

    static Color HexColor(string hex)
    {
        Color c;
        ColorUtility.TryParseHtmlString("#" + hex, out c);
        return c;
    }

    void Awake()
    {
        CreateUI();
    }

    void Start()
    {
        StartStory();
    }

    void StartStory()
    {
        StopAllCoroutines();

        for (int i = content.childCount - 1; i >= 0; i--)
            Destroy(content.GetChild(i).gameObject);
        choiceButtons.Clear();

        bottomPanel.SetActive(false);

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

    // --- Story Handlers ---

    void OnDialogue(Interpreter.Dialogue dialogue)
    {
        StartCoroutine(ShowDialogue(dialogue));
    }

    IEnumerator ShowDialogue(Interpreter.Dialogue dialogue)
    {
        string character = dialogue.Character;
        if (character != null)
        {
            string displayName = (string)dialogue.Interpreter.GetCharacterField(character, "name");
            if (displayName != null) character = displayName;
        }
        var obj = AddTextBlock(character, dialogue.Text);
        StartCoroutine(FadeIn(obj));
        yield return StartCoroutine(SmoothScrollToBottom());
        yield return new WaitForSeconds(1.5f);
        dialogue.Callback();
    }

    void OnChoice(Interpreter.Choice choice)
    {
        StartCoroutine(ShowChoices(choice));
    }

    IEnumerator ShowChoices(Interpreter.Choice choice)
    {
        yield return new WaitForSeconds(0.15f);

        // Extra spacing before choice block
        var spacer = CreateUIObject("Spacer", content);
        var sle = spacer.AddComponent<LayoutElement>();
        sle.minHeight = 6;

        for (int i = 0; i < choice.Options.Length; i++)
        {
            var opt = choice.Options[i];
            if (!opt.Enabled) continue;
            int index = i;
            GameObject btnObj = null;
            btnObj = AddChoiceButton(opt.Text, () =>
            {
                MarkChoiceSelected(btnObj);
                StartCoroutine(AfterChoiceSelected(() => choice.Callback(index)));
            });
            StartCoroutine(FadeIn(btnObj));
        }
        yield return StartCoroutine(SmoothScrollToBottom());
    }

    IEnumerator AfterChoiceSelected(System.Action callback)
    {
        yield return StartCoroutine(SmoothScrollToBottom());
        yield return new WaitForSeconds(0.3f);

        // Extra spacing after choice block
        var spacer = CreateUIObject("Spacer", content);
        var le = spacer.AddComponent<LayoutElement>();
        le.minHeight = 6;

        callback();
    }

    void OnFinish(Interpreter.Finish finish)
    {
        StartCoroutine(ShowFinish());
    }

    IEnumerator ShowFinish()
    {
        var obj = AddEndBlock();
        StartCoroutine(FadeIn(obj));
        yield return StartCoroutine(SmoothScrollToBottom());
        ShowRestartButton();
    }

    // --- UI Creation ---

    void CreateUI()
    {
        if (FindAnyObjectByType<EventSystem>() == null)
        {
            var esObj = new GameObject("EventSystem");
            esObj.AddComponent<EventSystem>();
            esObj.AddComponent<InputSystemUIInputModule>();
        }

        // Canvas
        var canvasObj = new GameObject("LorelineCanvas");
        canvasObj.transform.SetParent(transform);
        var canvas = canvasObj.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 100;

        var scaler = canvasObj.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(800, 600);
        scaler.matchWidthOrHeight = 0.5f;

        canvasObj.AddComponent<GraphicRaycaster>();

        // Scroll View — fills entire screen
        var scrollObj = CreateUIObject("ScrollView", canvasObj.transform);
        var scrollRectTransform = scrollObj.GetComponent<RectTransform>();
        StretchFill(scrollRectTransform);
        scrollObj.AddComponent<Image>().color = ContentBg;

        scrollRect = scrollObj.AddComponent<ScrollRect>();
        scrollRect.horizontal = false;
        scrollRect.movementType = ScrollRect.MovementType.Elastic;
        scrollRect.elasticity = 0.1f;
        scrollRect.scrollSensitivity = 30f;

        // Viewport
        var viewportObj = CreateUIObject("Viewport", scrollObj.transform);
        var viewportRect = viewportObj.GetComponent<RectTransform>();
        StretchFill(viewportRect);
        viewportObj.AddComponent<Image>().color = ContentBg;
        viewportObj.AddComponent<Mask>().showMaskGraphic = true;
        scrollRect.viewport = viewportRect;

        // Content container
        var contentObj = CreateUIObject("Content", viewportObj.transform);
        content = contentObj.GetComponent<RectTransform>();
        content.anchorMin = new Vector2(0, 1);
        content.anchorMax = new Vector2(1, 1);
        content.pivot = new Vector2(0.5f, 1);
        content.sizeDelta = new Vector2(0, 0);

        var vlg = contentObj.AddComponent<VerticalLayoutGroup>();
        vlg.padding = new RectOffset(32, 32, 32, 80);
        vlg.spacing = 16;
        vlg.childForceExpandWidth = true;
        vlg.childForceExpandHeight = false;
        vlg.childControlWidth = true;
        vlg.childControlHeight = true;

        var csf = contentObj.AddComponent<ContentSizeFitter>();
        csf.verticalFit = ContentSizeFitter.FitMode.PreferredSize;

        scrollRect.content = content;

        // Scrollbar — subtle, matching theme
        var scrollbarObj = CreateUIObject("Scrollbar", scrollObj.transform);
        var scrollbarRect = scrollbarObj.GetComponent<RectTransform>();
        scrollbarRect.anchorMin = new Vector2(1, 0);
        scrollbarRect.anchorMax = new Vector2(1, 1);
        scrollbarRect.pivot = new Vector2(1, 0.5f);
        scrollbarRect.sizeDelta = new Vector2(8, -8);
        scrollbarRect.anchoredPosition = new Vector2(-4, 0);
        scrollbarObj.AddComponent<Image>().color = new Color(0, 0, 0, 0);
        var scrollbar = scrollbarObj.AddComponent<Scrollbar>();
        scrollbar.direction = Scrollbar.Direction.BottomToTop;

        var handleObj = CreateUIObject("Handle", scrollbarObj.transform);
        StretchFill(handleObj.GetComponent<RectTransform>());
        var handleImg = handleObj.AddComponent<Image>();
        handleImg.color = HexColor("2a2a48");
        scrollbar.handleRect = handleObj.GetComponent<RectTransform>();
        scrollbar.targetGraphic = handleImg;
        scrollRect.verticalScrollbar = scrollbar;
        scrollRect.verticalScrollbarVisibility = ScrollRect.ScrollbarVisibility.AutoHide;

        // Bottom bar — only used for restart
        bottomPanel = CreateUIObject("BottomBar", canvasObj.transform);
        var bottomRect = bottomPanel.GetComponent<RectTransform>();
        bottomRect.anchorMin = new Vector2(0, 0);
        bottomRect.anchorMax = new Vector2(1, 0);
        bottomRect.pivot = new Vector2(0.5f, 0);
        bottomRect.sizeDelta = new Vector2(0, 56);
        bottomRect.anchoredPosition = Vector2.zero;
        bottomPanel.AddComponent<Image>().color = BottomBarBg;

        var restartBtnObj = CreateTextButton("RestartBtn", bottomPanel.transform, "Play Again", AccentColor);
        var restartBtnRect = restartBtnObj.GetComponent<RectTransform>();
        restartBtnRect.anchorMin = new Vector2(0.5f, 0.5f);
        restartBtnRect.anchorMax = new Vector2(0.5f, 0.5f);
        restartBtnRect.sizeDelta = new Vector2(200, 40);
        restartBtnRect.anchoredPosition = Vector2.zero;
        restartButton = restartBtnObj.GetComponent<Button>();
        restartButton.onClick.AddListener(() => StartStory());

        bottomPanel.SetActive(false);
    }

    // --- Text & Choice Methods ---

    GameObject AddTextBlock(string character, string text)
    {
        var obj = CreateUIObject("TextBlock", content);
        var textComp = obj.AddComponent<Text>();
        textComp.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        textComp.fontSize = 18;
        textComp.supportRichText = true;
        textComp.lineSpacing = 1.3f;

        if (character != null)
        {
            string colorHex;
            if (!CharacterColors.TryGetValue(character, out colorHex))
                colorHex = "#b0b0c0";

            textComp.text = "<color=" + colorHex + "><b>" + character + ":</b></color>  " + text;
            textComp.color = TextColor;
        }
        else
        {
            textComp.text = text;
            textComp.color = NarratorColor;
            textComp.fontStyle = FontStyle.Italic;
        }

        var layout = obj.AddComponent<LayoutElement>();
        layout.minHeight = 28;

        return obj;
    }

    GameObject AddEndBlock()
    {
        var obj = CreateUIObject("EndBlock", content);
        var textComp = obj.AddComponent<Text>();
        textComp.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        textComp.fontSize = 20;
        textComp.text = "\u2014 The End \u2014";
        textComp.color = AccentColor;
        textComp.fontStyle = FontStyle.Italic;
        textComp.alignment = TextAnchor.MiddleCenter;

        var layout = obj.AddComponent<LayoutElement>();
        layout.minHeight = 48;

        return obj;
    }

    GameObject AddChoiceButton(string text, System.Action onClick)
    {
        var btnObj = CreateUIObject("Choice", content);

        var btnImg = btnObj.AddComponent<Image>();
        btnImg.color = ChoiceBg;

        var btn = btnObj.AddComponent<Button>();
        btn.transition = Selectable.Transition.None;
        btn.targetGraphic = btnImg;
        btn.onClick.AddListener(() => onClick());

        // Text child
        var textObj = CreateUIObject("Text", btnObj.transform);
        var textRect = textObj.GetComponent<RectTransform>();
        StretchFill(textRect);
        textRect.offsetMin = new Vector2(20, 8);
        textRect.offsetMax = new Vector2(-20, -8);

        var textComp = textObj.AddComponent<Text>();
        textComp.text = text;
        textComp.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        textComp.fontSize = 17;
        textComp.color = ChoiceText;
        textComp.alignment = TextAnchor.MiddleLeft;

        var layoutEl = btnObj.AddComponent<LayoutElement>();
        layoutEl.minHeight = 50;

        choiceButtons.Add(btnObj);

        return btnObj;
    }

    void MarkChoiceSelected(GameObject selectedBtn)
    {
        foreach (var btn in choiceButtons)
        {
            if (btn == selectedBtn)
            {
                btn.GetComponent<Button>().interactable = false;
            }
            else
            {
                // Dim non-selected choices
                btn.GetComponent<Button>().interactable = false;
                btn.GetComponent<Image>().color = HexColor("1a1a30");
                var text = btn.GetComponentInChildren<Text>();
                if (text != null) text.color = HexColor("505068");
            }
        }
        choiceButtons.Clear();
    }

    void ShowRestartButton()
    {
        bottomPanel.SetActive(true);
        restartButton.gameObject.SetActive(true);
    }

    // --- Animation Helpers ---

    IEnumerator FadeIn(GameObject obj, float duration = 0.3f)
    {
        var cg = obj.AddComponent<CanvasGroup>();
        cg.alpha = 0f;
        float elapsed = 0f;
        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            cg.alpha = Mathf.Clamp01(elapsed / duration);
            yield return null;
        }
        cg.alpha = 1f;
    }

    IEnumerator SmoothScrollToBottom()
    {
        yield return new WaitForEndOfFrame();
        Canvas.ForceUpdateCanvases();

        float start = scrollRect.verticalNormalizedPosition;
        if (start <= 0.01f) yield break;

        float duration = 0.25f;
        float elapsed = 0f;
        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = Mathf.SmoothStep(0f, 1f, elapsed / duration);
            scrollRect.verticalNormalizedPosition = Mathf.Lerp(start, 0f, t);
            yield return null;
        }
        scrollRect.verticalNormalizedPosition = 0f;
    }

    // --- UI Helpers ---

    GameObject CreateUIObject(string name, Transform parent)
    {
        var obj = new GameObject(name, typeof(RectTransform));
        obj.transform.SetParent(parent, false);
        return obj;
    }

    void StretchFill(RectTransform rect)
    {
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
    }

    GameObject CreateTextButton(string name, Transform parent, string label, Color textColor)
    {
        var btnObj = CreateUIObject(name, parent);

        var btnImg = btnObj.AddComponent<Image>();
        btnImg.color = new Color(0, 0, 0, 0);

        var btn = btnObj.AddComponent<Button>();
        btn.targetGraphic = btnImg;

        var colors = btn.colors;
        colors.normalColor = new Color(1, 1, 1, 0);
        colors.highlightedColor = new Color(1, 1, 1, 0.05f);
        colors.pressedColor = new Color(1, 1, 1, 0.1f);
        colors.selectedColor = new Color(1, 1, 1, 0);
        colors.fadeDuration = 0.1f;
        btn.colors = colors;

        var textObj = CreateUIObject("Text", btnObj.transform);
        var textRect = textObj.GetComponent<RectTransform>();
        StretchFill(textRect);

        var textComp = textObj.AddComponent<Text>();
        textComp.text = label;
        textComp.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        textComp.fontSize = 16;
        textComp.color = textColor;
        textComp.alignment = TextAnchor.MiddleCenter;

        return btnObj;
    }
}
