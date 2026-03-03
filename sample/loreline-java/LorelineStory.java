import loreline.*;

import javax.swing.*;
import javax.swing.plaf.basic.BasicScrollBarUI;
import java.awt.*;
import java.awt.event.*;
import java.awt.font.*;
import java.awt.geom.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.text.*;
import java.util.ArrayList;
import java.util.List;

/**
 * Loreline Java Desktop Sample — Swing application.
 *
 * A self-contained story player that matches the visual design of the
 * loreline-web and loreline-unity samples. Uses Java2D custom painting
 * for gradient character names, italic narrative text, animated choice
 * buttons, and smooth scrolling.
 *
 * Usage:
 *   mkdir -p build
 *   javac -cp loreline.jar -d build LorelineStory.java
 *   java -cp "loreline.jar:build" LorelineStory
 */
public class LorelineStory extends JFrame {

    // ── Theme Colors (matching web sample CSS variables) ─────────────────────

    static final Color BG        = new Color(0x15, 0x13, 0x1b);
    static final Color TEXT       = new Color(0xf0, 0xee, 0xf5);
    static final Color TEXT_MUTED = new Color(0xa0, 0x9c, 0xb0);
    static final Color TEXT_DIM   = new Color(0x6b, 0x65, 0x80);
    static final Color BORDER     = new Color(0x2e, 0x2a, 0x3a);
    static final Color PURPLE     = new Color(0x8b, 0x5c, 0xf6);
    static final Color GLOW       = new Color(139, 92, 246, 26); // ~0.1 alpha

    // Gradient stops for character names: #ff5eab → #8b5cf6 (40%) → #56a0f6
    static final Color GRAD_0 = new Color(0xff, 0x5e, 0xab);
    static final Color GRAD_1 = new Color(0x8b, 0x5c, 0xf6);
    static final Color GRAD_2 = new Color(0x56, 0xa0, 0xf6);

    // ── Fonts ────────────────────────────────────────────────────────────────

    static Font narrativeFont; // Literata Italic
    static Font dialogueFont;  // Outfit Regular
    static Font nameBoldFont;  // Outfit SemiBold (weight 600)
    static Font choiceFont;    // Outfit Regular, smaller
    static Font resetFont;     // Outfit Regular, smaller still

    // ── Layout Constants ─────────────────────────────────────────────────────

    static final int CONTENT_WIDTH = 700;
    static final int SIDE_PAD = 16;
    static final int LINE_PAD_V = 2;       // vertical padding per line
    static final float LINE_HEIGHT = 1.7f;

    // ── Instance State ───────────────────────────────────────────────────────

    private final JPanel contentPanel;
    private final JPanel heightKeeper;
    private final JScrollPane scrollPane;
    private final List<Timer> pendingTimers = new ArrayList<>();

    // Scroll animation
    private Timer scrollTimer;
    private long scrollStartTime;
    private int scrollStart, scrollDuration;

    // ── Constructor ──────────────────────────────────────────────────────────

    public LorelineStory() {
        super("Loreline \u2014 Java Sample");
        setDefaultCloseOperation(EXIT_ON_CLOSE);
        setSize(900, 700);
        setMinimumSize(new Dimension(400, 300));
        setLocationRelativeTo(null);
        getContentPane().setBackground(BG);

        // Content panel
        contentPanel = new JPanel();
        contentPanel.setLayout(new BoxLayout(contentPanel, BoxLayout.Y_AXIS));
        contentPanel.setOpaque(false);

        // Two-column wrapper (scroll-stable layout, matches web/Unity pattern).
        // Column 0: content (takes all width). Column 1: zero-width keeper whose
        // height only ever increases, preventing scroll jumps when choices hide.
        JPanel tableWrapper = new JPanel(new GridBagLayout());
        tableWrapper.setOpaque(false);

        GridBagConstraints contentGbc = new GridBagConstraints();
        contentGbc.gridx = 0;
        contentGbc.gridy = 0;
        contentGbc.weightx = 1;
        contentGbc.weighty = 0;
        contentGbc.fill = GridBagConstraints.HORIZONTAL;
        contentGbc.anchor = GridBagConstraints.NORTH;
        contentGbc.insets = new Insets(32, 24, 200, 0);
        tableWrapper.add(contentPanel, contentGbc);

        heightKeeper = new JPanel();
        heightKeeper.setOpaque(false);
        heightKeeper.setPreferredSize(new Dimension(0, 0));
        GridBagConstraints keeperGbc = new GridBagConstraints();
        keeperGbc.gridx = 1;
        keeperGbc.gridy = 0;
        keeperGbc.weightx = 0;
        keeperGbc.weighty = 0;
        keeperGbc.fill = GridBagConstraints.VERTICAL;
        keeperGbc.insets = new Insets(32, 0, 200, 24);
        tableWrapper.add(heightKeeper, keeperGbc);

        // Wrap in NORTH panel to prevent viewport stretching
        JPanel northWrapper = new JPanel(new BorderLayout());
        northWrapper.setOpaque(false);
        northWrapper.add(tableWrapper, BorderLayout.NORTH);

        // Scroll pane
        scrollPane = new JScrollPane(northWrapper);
        scrollPane.setBorder(null);
        scrollPane.getViewport().setBackground(BG);
        scrollPane.setHorizontalScrollBarPolicy(ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER);
        scrollPane.getVerticalScrollBar().setUnitIncrement(16);
        scrollPane.getVerticalScrollBar().setUI(new DarkScrollBarUI());
        scrollPane.getVerticalScrollBar().setPreferredSize(new Dimension(7, 0));

        getContentPane().setLayout(new BorderLayout());
        getContentPane().add(scrollPane, BorderLayout.CENTER);
    }

    // ── Story Loading ────────────────────────────────────────────────────────

    private void startStory() {
        clearOutput();

        String storyDir = "story" + File.separator;
        String content = readFile(storyDir + "CoffeeShop.lor");
        if (content == null) {
            appendNarrative("Error: Could not read story/CoffeeShop.lor");
            return;
        }

        Script script = Loreline.parse(content, "CoffeeShop.lor",
            path -> readFile(storyDir + path));

        if (script == null) {
            appendNarrative("Error: Failed to parse script.");
            return;
        }

        Loreline.play(script, this::onDialogue, this::onChoice, this::onFinish);
    }

    private String readFile(String path) {
        try {
            return new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return null;
        }
    }

    // ── Loreline Handlers ────────────────────────────────────────────────────

    private void onDialogue(Interpreter interp, String character, String text,
                            List<TextTag> tags, Runnable advance) {
        String displayName = character;
        if (character != null) {
            try {
                Object n = interp.getCharacterField(character, "name");
                if (n != null) displayName = n.toString();
            } catch (Exception e) { /* fallback to original */ }
        }

        if (displayName != null) {
            appendDialogue(displayName, text);
        } else {
            appendNarrative(text);
        }

        // Auto-advance after 600ms
        scheduleDelayed(600, advance);
    }

    private void onChoice(Interpreter interp, List<ChoiceOption> options,
                          java.util.function.IntConsumer select) {
        // Show choices after brief delay
        scheduleDelayed(250, () -> showChoices(options, select));
    }

    private void onFinish(Interpreter interp) {
        showFinished();
    }

    // ── Rendering: Dialogue & Narrative ──────────────────────────────────────

    private void appendNarrative(String text) {
        StoryLine line = new StoryLine(null, text);
        addLineComponent(line);
    }

    private void appendDialogue(String character, String text) {
        StoryLine line = new StoryLine(character, text);
        addLineComponent(line);
    }

    private void addLineComponent(JComponent comp) {
        comp.setAlignmentX(0.0f);
        comp.setMaximumSize(new Dimension(CONTENT_WIDTH, Integer.MAX_VALUE));
        contentPanel.add(comp);
        updateHeightKeeper();
        contentPanel.revalidate();
        fadeIn(comp);
        scrollToBottom();
    }

    // ── Rendering: Choices ───────────────────────────────────────────────────

    private void showChoices(List<ChoiceOption> options,
                             java.util.function.IntConsumer callback) {
        JPanel choiceContainer = new JPanel();
        choiceContainer.setLayout(new BoxLayout(choiceContainer, BoxLayout.Y_AXIS));
        choiceContainer.setOpaque(false);
        choiceContainer.setAlignmentX(0.0f);
        choiceContainer.setMaximumSize(new Dimension(CONTENT_WIDTH, Integer.MAX_VALUE));

        // Top margin for the choice container
        choiceContainer.setBorder(BorderFactory.createEmptyBorder(12, 0, 0, 0));

        List<ChoiceButton> buttons = new ArrayList<>();
        boolean[] selected = {false};

        for (int i = 0; i < options.size(); i++) {
            ChoiceOption opt = options.get(i);
            if (!opt.enabled) continue;

            int idx = i;
            ChoiceButton btn = new ChoiceButton(opt.text);
            btn.setAlignmentX(0.0f);
            btn.setMaximumSize(new Dimension(CONTENT_WIDTH, Integer.MAX_VALUE));

            // Top margin between buttons (skip first)
            if (!buttons.isEmpty()) {
                btn.setBorder(BorderFactory.createEmptyBorder(6, 0, 0, 0));
            }

            btn.addMouseListener(new MouseAdapter() {
                @Override
                public void mouseClicked(MouseEvent e) {
                    if (selected[0]) return;
                    selected[0] = true;

                    // Phase 1: highlight selected, fade others (no layout change)
                    for (ChoiceButton b : buttons) {
                        if (b == btn) {
                            b.setSelected(true);
                        } else {
                            b.setFading(true);
                        }
                    }
                    choiceContainer.repaint();

                    // Phase 2 (300ms): collapse non-selected + animate selected border
                    scheduleDelayed(300, () -> {
                        java.util.LinkedHashMap<ChoiceButton, Integer> origHeights =
                            new java.util.LinkedHashMap<>();
                        for (ChoiceButton b : buttons) {
                            if (b != btn) origHeights.put(b, b.getHeight());
                        }
                        int origTop = btn.getInsets().top;

                        Timer collapseTimer = new Timer(16, null);
                        long start = System.currentTimeMillis();
                        collapseTimer.addActionListener(ev -> {
                            float t = Math.min(1f, (System.currentTimeMillis() - start) / 350f);
                            float ease = t < 0.5f ? 2 * t * t : -1 + (4 - 2 * t) * t;

                            for (java.util.Map.Entry<ChoiceButton, Integer> entry : origHeights.entrySet()) {
                                ChoiceButton b = entry.getKey();
                                int origH = entry.getValue();
                                int newH = Math.max(0, (int) (origH * (1f - ease)));
                                Dimension d = new Dimension(b.getWidth(), newH);
                                b.setPreferredSize(d);
                                b.setMaximumSize(d);
                                b.setMinimumSize(new Dimension(0, newH));
                            }
                            // Animate selected button border: top shrinks, bottom grows
                            int curTop = (int) (origTop * (1f - ease));
                            int curBottom = (int) (19 * ease);
                            btn.setBorder(BorderFactory.createEmptyBorder(curTop, 0, curBottom, 0));

                            choiceContainer.revalidate();
                            choiceContainer.repaint();

                            if (t >= 1f) collapseTimer.stop();
                        });
                        pendingTimers.add(collapseTimer);
                        collapseTimer.start();
                    });

                    // Phase 3 (700ms): hide others, continue story
                    scheduleDelayed(700, () -> {
                        for (ChoiceButton b : buttons) {
                            if (b != btn) b.setVisible(false);
                        }
                        btn.setBorder(BorderFactory.createEmptyBorder(0, 0, 19, 0));
                        choiceContainer.revalidate();
                        choiceContainer.repaint();
                        updateHeightKeeper();
                        callback.accept(idx);
                    });
                }

                @Override
                public void mouseEntered(MouseEvent e) {
                    if (!selected[0]) btn.setHovered(true);
                }

                @Override
                public void mouseExited(MouseEvent e) {
                    btn.setHovered(false);
                }
            });

            buttons.add(btn);
            choiceContainer.add(btn);
        }

        addLineComponent(choiceContainer);
    }

    // ── Rendering: Story Finished ────────────────────────────────────────────

    private void showFinished() {
        scheduleDelayed(500, () -> {
            ResetButton resetBtn = new ResetButton("Play again");
            resetBtn.setAlignmentX(0.0f);
            resetBtn.setMaximumSize(new Dimension(CONTENT_WIDTH, Integer.MAX_VALUE));
            resetBtn.setBorder(BorderFactory.createEmptyBorder(18, 0, 0, 0));
            resetBtn.addMouseListener(new MouseAdapter() {
                @Override
                public void mouseClicked(MouseEvent e) { startStory(); }

                @Override
                public void mouseEntered(MouseEvent e) { resetBtn.setHovered(true); }

                @Override
                public void mouseExited(MouseEvent e) { resetBtn.setHovered(false); }
            });
            addLineComponent(resetBtn);
        });
    }

    // ── Animation: Fade In ───────────────────────────────────────────────────

    private void fadeIn(JComponent comp) {
        comp.putClientProperty("fadeAlpha", 0f);
        comp.putClientProperty("fadeOffsetY", 4f);

        Timer timer = new Timer(16, null);
        long start = System.currentTimeMillis();
        timer.addActionListener(e -> {
            float t = Math.min(1f, (System.currentTimeMillis() - start) / 450f);
            float ease = t < 0.5f ? 2 * t * t : -1 + (4 - 2 * t) * t;
            comp.putClientProperty("fadeAlpha", ease);
            comp.putClientProperty("fadeOffsetY", 4f * (1f - ease));
            comp.repaint();
            if (t >= 1f) {
                timer.stop();
                comp.putClientProperty("fadeAlpha", 1f);
                comp.putClientProperty("fadeOffsetY", 0f);
            }
        });
        pendingTimers.add(timer);
        timer.start();
    }

    static float getFadeAlpha(JComponent c) {
        Object v = c.getClientProperty("fadeAlpha");
        return v instanceof Float ? (Float) v : 1f;
    }

    static float getFadeOffsetY(JComponent c) {
        Object v = c.getClientProperty("fadeOffsetY");
        return v instanceof Float ? (Float) v : 0f;
    }

    // ── Animation: Smooth Scroll ─────────────────────────────────────────────

    private void scrollToBottom() {
        SwingUtilities.invokeLater(() -> {
            JScrollBar vb = scrollPane.getVerticalScrollBar();
            int target = vb.getMaximum() - vb.getVisibleAmount();
            int start = vb.getValue();
            if (target <= start) return;

            int dist = target - start;
            int dur = Math.min(600, Math.max(250, (int) (dist * 1.2)));

            if (scrollTimer != null) scrollTimer.stop();
            scrollStart = start;
            scrollDuration = dur;
            scrollStartTime = System.currentTimeMillis();

            scrollTimer = new Timer(16, e -> {
                float t = Math.min(1f, (System.currentTimeMillis() - scrollStartTime)
                                       / (float) scrollDuration);
                float ease = t < 0.5f ? 2 * t * t : -1 + (4 - 2 * t) * t;
                int liveTarget = vb.getMaximum() - vb.getVisibleAmount();
                vb.setValue(scrollStart + (int) ((liveTarget - scrollStart) * ease));
                if (t >= 1f) {
                    scrollTimer.stop();
                    scrollTimer = null;
                }
            });
            scrollTimer.start();
        });
    }

    // ── Timer Management ─────────────────────────────────────────────────────

    private void scheduleDelayed(int delayMs, Runnable action) {
        Timer t = new Timer(delayMs, e -> action.run());
        t.setRepeats(false);
        pendingTimers.add(t);
        t.start();
    }

    private void clearTimers() {
        for (Timer t : pendingTimers) t.stop();
        pendingTimers.clear();
        if (scrollTimer != null) { scrollTimer.stop(); scrollTimer = null; }
    }

    private void clearOutput() {
        clearTimers();
        contentPanel.removeAll();
        heightKeeper.setPreferredSize(new Dimension(0, 0));
        contentPanel.revalidate();
        contentPanel.repaint();
        scrollPane.getVerticalScrollBar().setValue(0);
    }

    private void updateHeightKeeper() {
        int h = contentPanel.getPreferredSize().height;
        int current = heightKeeper.getPreferredSize().height;
        if (h > current) {
            heightKeeper.setPreferredSize(new Dimension(0, h));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  INNER CLASSES — Custom Components
    // ══════════════════════════════════════════════════════════════════════════

    // ── StoryLine: Narrative & Dialogue ───────────────────────────────────────

    /**
     * Custom-painted component for a single line of narrative or dialogue.
     * Narrative: italic Literata, muted color.
     * Dialogue: gradient character name (bold Outfit) + text (regular Outfit).
     */
    static class StoryLine extends JPanel {
        final String character; // null for narrative
        final String text;

        StoryLine(String character, String text) {
            this.character = character;
            this.text = text;
            setOpaque(false);
            // Bottom margin: dialogue gets more space, narrative tighter
            int bottomMargin = character != null ? 13 : 10;
            setBorder(BorderFactory.createEmptyBorder(LINE_PAD_V, 0, bottomMargin, 0));
        }

        @Override
        public Dimension getPreferredSize() {
            int w = getParent() != null ? getParent().getWidth() : CONTENT_WIDTH;
            if (w <= 0) w = CONTENT_WIDTH;
            Insets ins = getInsets();
            int contentW = w - ins.left - ins.right;
            int h = ins.top + ins.bottom + computeTextHeight(contentW);
            return new Dimension(w, h);
        }

        private int computeTextHeight(int width) {
            if (width <= 0) return 20;
            java.awt.image.BufferedImage img =
                new java.awt.image.BufferedImage(1, 1, java.awt.image.BufferedImage.TYPE_INT_ARGB);
            Graphics2D g2 = img.createGraphics();

            int h;
            if (character != null) {
                h = measureDialogueHeight(g2, width);
            } else {
                h = measureWrappedHeight(g2, narrativeFont, text, width);
            }
            g2.dispose();
            return h;
        }

        private int measureDialogueHeight(Graphics2D g2, int width) {
            String nameStr = character + "\u2009:\u2004\u200a";
            String full = nameStr + text;

            AttributedString as = new AttributedString(full);
            as.addAttribute(TextAttribute.FONT, nameBoldFont, 0, nameStr.length());
            as.addAttribute(TextAttribute.FONT, dialogueFont, nameStr.length(), full.length());

            float leading = dialogueFont.getSize2D() * (LINE_HEIGHT - 1f);
            return measureAttributedHeight(g2, as, full, width, leading);
        }

        static int measureWrappedHeight(Graphics2D g2, Font font, String text, int width) {
            if (text == null || text.isEmpty()) return (int) font.getSize2D();
            AttributedString as = new AttributedString(text);
            as.addAttribute(TextAttribute.FONT, font);
            float leading = font.getSize2D() * (LINE_HEIGHT - 1f);
            return measureAttributedHeight(g2, as, text, width, leading);
        }

        static int measureAttributedHeight(Graphics2D g2, AttributedString as,
                                            String text, int width, float leading) {
            g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
                                RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
            FontRenderContext frc = g2.getFontRenderContext();
            AttributedCharacterIterator aci = as.getIterator();
            LineBreakMeasurer lbm = new LineBreakMeasurer(aci, frc);

            float h = 0;
            boolean first = true;
            while (lbm.getPosition() < text.length()) {
                TextLayout layout = lbm.nextLayout(width);
                if (!first) h += leading;
                h += layout.getAscent() + layout.getDescent() + layout.getLeading();
                first = false;
            }
            return (int) Math.ceil(h);
        }

        @Override
        protected void paintComponent(Graphics g) {
            super.paintComponent(g);
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
                                RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
            g2.setRenderingHint(RenderingHints.KEY_RENDERING,
                                RenderingHints.VALUE_RENDER_QUALITY);

            // Apply fade
            float alpha = getFadeAlpha(this);
            float offsetY = getFadeOffsetY(this);
            g2.setComposite(AlphaComposite.SrcOver.derive(alpha));
            g2.translate(0, offsetY);

            Insets ins = getInsets();
            int contentW = getWidth() - ins.left - ins.right;
            float x = ins.left;
            float y = ins.top;

            if (character != null) {
                paintDialogue(g2, x, y, contentW);
            } else {
                paintNarrative(g2, x, y, contentW);
            }
            g2.dispose();
        }

        private void paintNarrative(Graphics2D g2, float x, float y, int width) {
            g2.setColor(TEXT_MUTED);
            AttributedString as = new AttributedString(text);
            as.addAttribute(TextAttribute.FONT, narrativeFont);

            drawWrappedText(g2, as, text, x, y, width,
                            narrativeFont.getSize2D() * (LINE_HEIGHT - 1f));
        }

        private void paintDialogue(Graphics2D g2, float x, float y, int width) {
            String nameStr = character + "\u2009:\u2004\u200a";
            String full = nameStr + text;

            AttributedString as = new AttributedString(full);
            as.addAttribute(TextAttribute.FONT, nameBoldFont, 0, nameStr.length());
            as.addAttribute(TextAttribute.FONT, dialogueFont, nameStr.length(), full.length());

            // We need to draw with gradient for the name part
            FontRenderContext frc = g2.getFontRenderContext();
            AttributedCharacterIterator aci = as.getIterator();
            LineBreakMeasurer lbm = new LineBreakMeasurer(aci, frc);

            float leading = dialogueFont.getSize2D() * (LINE_HEIGHT - 1f);
            float curY = y;
            int charPos = 0;
            boolean first = true;

            while (lbm.getPosition() < full.length()) {
                TextLayout layout = lbm.nextLayout(width);
                if (!first) curY += leading;
                curY += layout.getAscent();

                int lineEnd = lbm.getPosition();

                // If this line overlaps with the name portion, draw with gradient
                if (charPos < nameStr.length()) {
                    // Draw the line in segments: name part with gradient, text part with TEXT color
                    int nameEndInLine = Math.min(nameStr.length(), lineEnd) - charPos;

                    // Create attributed string for just this line
                    String lineStr = full.substring(charPos, lineEnd);
                    AttributedString lineAs = new AttributedString(lineStr);
                    // Copy font attributes
                    for (int ci = 0; ci < lineStr.length(); ci++) {
                        int fullIdx = charPos + ci;
                        Font f = fullIdx < nameStr.length() ? nameBoldFont : dialogueFont;
                        lineAs.addAttribute(TextAttribute.FONT, f, ci, ci + 1);
                    }

                    // Measure name width for gradient paint
                    AttributedString namePartAs = new AttributedString(
                        lineStr.substring(0, nameEndInLine));
                    namePartAs.addAttribute(TextAttribute.FONT, nameBoldFont);
                    TextLayout nameLayout = new TextLayout(
                        namePartAs.getIterator(), frc);
                    float nameWidth = nameLayout.getAdvance();

                    // Draw name part with gradient (narrower range matching Unity's 0.30–0.70)
                    if (nameWidth > 1) {
                        float fullW = nameWidth / 0.40f;
                        float gx0 = x - 0.30f * fullW;
                        float gx1 = gx0 + fullW;
                        Paint gradPaint = new LinearGradientPaint(
                            gx0, curY, gx1, curY,
                            new float[]{0f, 0.4f, 1f},
                            new Color[]{GRAD_0, GRAD_1, GRAD_2});
                        g2.setPaint(gradPaint);

                        // Draw only name portion
                        AttributedString nameOnlyAs = new AttributedString(
                            lineStr.substring(0, nameEndInLine));
                        nameOnlyAs.addAttribute(TextAttribute.FONT, nameBoldFont);
                        TextLayout nameOnlyLayout = new TextLayout(
                            nameOnlyAs.getIterator(), frc);
                        nameOnlyLayout.draw(g2, x, curY);
                    }

                    // Draw text part with TEXT color
                    if (nameEndInLine < lineStr.length()) {
                        String textPart = lineStr.substring(nameEndInLine);
                        AttributedString textAs = new AttributedString(textPart);
                        textAs.addAttribute(TextAttribute.FONT, dialogueFont);
                        TextLayout textLayout = new TextLayout(
                            textAs.getIterator(), frc);
                        g2.setColor(TEXT);
                        textLayout.draw(g2, x + nameWidth, curY);
                    }
                } else {
                    // Pure text line
                    g2.setColor(TEXT);
                    layout.draw(g2, x, curY);
                }

                curY += layout.getDescent() + layout.getLeading();
                charPos = lineEnd;
                first = false;
            }
        }

        static void drawWrappedText(Graphics2D g2, AttributedString as, String text,
                                     float x, float y, int width, float leading) {
            if (text == null || text.isEmpty()) return;
            FontRenderContext frc = g2.getFontRenderContext();
            AttributedCharacterIterator aci = as.getIterator();
            LineBreakMeasurer lbm = new LineBreakMeasurer(aci, frc);

            float curY = y;
            boolean first = true;
            while (lbm.getPosition() < text.length()) {
                TextLayout layout = lbm.nextLayout(width);
                if (!first) curY += leading;
                curY += layout.getAscent();
                layout.draw(g2, x, curY);
                curY += layout.getDescent() + layout.getLeading();
                first = false;
            }
        }
    }

    // ── ChoiceButton ─────────────────────────────────────────────────────────

    /**
     * Custom-painted choice button with rounded rect border, hover, selected,
     * and fading states.
     */
    static class ChoiceButton extends JPanel {
        final String text;
        private boolean hovered, isSelected, fading;
        private float fadeAlpha = 1f;

        ChoiceButton(String text) {
            this.text = text;
            setOpaque(false);
            setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        }

        void setHovered(boolean h) {
            hovered = h;
            repaint();
        }

        void setSelected(boolean s) {
            isSelected = s;
            setCursor(Cursor.getDefaultCursor());
            repaint();
        }

        void setFading(boolean f) {
            fading = f;
            if (f) {
                Timer t = new Timer(16, null);
                long start = System.currentTimeMillis();
                t.addActionListener(e -> {
                    float p = Math.min(1f, (System.currentTimeMillis() - start) / 250f);
                    fadeAlpha = 1f - p;
                    repaint();
                    if (p >= 1f) t.stop();
                });
                t.start();
            }
        }

        @Override
        public Dimension getPreferredSize() {
            // During collapse animation, an explicit size is set — honor it
            if (isPreferredSizeSet()) {
                return super.getPreferredSize();
            }
            Insets ins = getInsets();
            int w = getParent() != null ? getParent().getWidth() : CONTENT_WIDTH;
            if (w <= 0) w = CONTENT_WIDTH;
            int padH = 14, padW = 14;
            int contentW = w - ins.left - ins.right - padW * 2;

            java.awt.image.BufferedImage img =
                new java.awt.image.BufferedImage(1, 1, java.awt.image.BufferedImage.TYPE_INT_ARGB);
            Graphics2D g2 = img.createGraphics();
            int textH = StoryLine.measureWrappedHeight(g2, choiceFont, text, contentW);
            g2.dispose();

            int h = ins.top + ins.bottom + padH * 2 + textH;
            return new Dimension(w, h);
        }

        @Override
        protected void paintComponent(Graphics g) {
            super.paintComponent(g);
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                                RenderingHints.VALUE_ANTIALIAS_ON);
            g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
                                RenderingHints.VALUE_TEXT_ANTIALIAS_ON);

            // Read fade from parent container (fadeIn is applied to choiceContainer)
            float containerAlpha = 1f;
            float containerOffsetY = 0f;
            Container parent = getParent();
            if (parent instanceof JComponent) {
                containerAlpha = getFadeAlpha((JComponent) parent);
                containerOffsetY = getFadeOffsetY((JComponent) parent);
            }
            float alpha = containerAlpha * fadeAlpha;
            g2.setComposite(AlphaComposite.SrcOver.derive(alpha));
            g2.translate(0, containerOffsetY);

            Insets ins = getInsets();
            int padH = 14, padW = 14;
            int rx = ins.left, ry = ins.top;
            int rw = getWidth() - ins.left - ins.right;
            int rh = getHeight() - ins.top - ins.bottom;

            // Background fill on hover/selected
            if (isSelected || hovered) {
                g2.setColor(GLOW);
                g2.fill(new RoundRectangle2D.Float(rx, ry, rw, rh, 16, 16));
            }

            // Border
            g2.setColor(isSelected || hovered ? PURPLE : BORDER);
            g2.setStroke(new BasicStroke(1f));
            g2.draw(new RoundRectangle2D.Float(rx + 0.5f, ry + 0.5f,
                                                rw - 1, rh - 1, 16, 16));

            // Text
            g2.setColor(isSelected || hovered ? TEXT : TEXT_MUTED);
            int contentW = rw - padW * 2;
            AttributedString as = new AttributedString(text);
            as.addAttribute(TextAttribute.FONT, choiceFont);
            StoryLine.drawWrappedText(g2, as, text,
                rx + padW, ry + padH, contentW,
                choiceFont.getSize2D() * (LINE_HEIGHT - 1f));

            g2.dispose();
        }
    }

    // ── ResetButton ──────────────────────────────────────────────────────────

    /** "Play again" button — smaller, dim text, same rounded style. */
    static class ResetButton extends JPanel {
        final String text;
        private boolean hovered;

        ResetButton(String text) {
            this.text = text;
            setOpaque(false);
            setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        }

        void setHovered(boolean h) { hovered = h; repaint(); }

        @Override
        public Dimension getPreferredSize() {
            Insets ins = getInsets();
            FontMetrics fm = getFontMetrics(resetFont);
            int tw = fm.stringWidth(text);
            int th = fm.getHeight();
            int padH = 7, padW = 12;
            return new Dimension(
                ins.left + ins.right + tw + padW * 2 + 2,
                ins.top + ins.bottom + th + padH * 2
            );
        }

        @Override
        protected void paintComponent(Graphics g) {
            super.paintComponent(g);
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                                RenderingHints.VALUE_ANTIALIAS_ON);
            g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
                                RenderingHints.VALUE_TEXT_ANTIALIAS_ON);

            float alpha = getFadeAlpha(this);
            float offsetY = getFadeOffsetY(this);
            g2.setComposite(AlphaComposite.SrcOver.derive(alpha));
            g2.translate(0, offsetY);

            Insets ins = getInsets();
            int padH = 7, padW = 12;
            FontMetrics fm = g2.getFontMetrics(resetFont);
            int tw = fm.stringWidth(text);
            int th = fm.getHeight();
            int rw = tw + padW * 2 + 2;
            int rh = th + padH * 2;
            int rx = ins.left, ry = ins.top;

            if (hovered) {
                g2.setColor(GLOW);
                g2.fill(new RoundRectangle2D.Float(rx, ry, rw, rh, 12, 12));
            }

            g2.setColor(hovered ? PURPLE : BORDER);
            g2.setStroke(new BasicStroke(1f));
            g2.draw(new RoundRectangle2D.Float(rx + 0.5f, ry + 0.5f,
                                                rw - 1, rh - 1, 12, 12));

            g2.setFont(resetFont);
            g2.setColor(hovered ? TEXT_MUTED : TEXT_DIM);
            g2.drawString(text, rx + padW + 1, ry + padH + fm.getAscent());

            g2.dispose();
        }
    }

    // ── DarkScrollBarUI ──────────────────────────────────────────────────────

    /** Minimal dark scrollbar matching the web sample's thin custom scrollbar. */
    static class DarkScrollBarUI extends BasicScrollBarUI {
        @Override
        protected void configureScrollBarColors() {
            trackColor = BG;
            thumbColor = BORDER;
        }

        @Override
        protected JButton createDecreaseButton(int orientation) {
            return zeroButton();
        }

        @Override
        protected JButton createIncreaseButton(int orientation) {
            return zeroButton();
        }

        private JButton zeroButton() {
            JButton b = new JButton();
            b.setPreferredSize(new Dimension(0, 0));
            return b;
        }

        @Override
        protected void paintTrack(Graphics g, JComponent c, Rectangle r) {
            g.setColor(BG);
            g.fillRect(r.x, r.y, r.width, r.height);
        }

        @Override
        protected void paintThumb(Graphics g, JComponent c, Rectangle r) {
            if (r.isEmpty()) return;
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                                RenderingHints.VALUE_ANTIALIAS_ON);
            g2.setColor(BORDER);
            g2.fill(new RoundRectangle2D.Float(r.x + 1, r.y, r.width - 2,
                                                r.height, 8, 8));
            g2.dispose();
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  MAIN
    // ══════════════════════════════════════════════════════════════════════════

    public static void main(String[] args) {
        // Load custom fonts
        loadFonts();

        SwingUtilities.invokeLater(() -> {
            // Set system look and feel for better native integration
            try {
                UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
            } catch (Exception ignored) {}

            LorelineStory app = new LorelineStory();
            app.setVisible(true);
            app.startStory();
        });
    }

    private static void loadFonts() {
        float baseSize = 17f;

        // Try loading custom fonts (same files as the Unity sample)
        Font literata = loadFont("fonts/Literata-Italic.ttf");
        Font outfit = loadFont("fonts/Outfit-Regular.ttf");
        Font outfitSemiBold = loadFont("fonts/Outfit-SemiBold.ttf");

        if (literata != null) {
            narrativeFont = literata.deriveFont(Font.ITALIC, baseSize);
        } else {
            narrativeFont = new Font("Georgia", Font.ITALIC, (int) baseSize);
        }

        if (outfit != null) {
            dialogueFont = outfit.deriveFont(Font.PLAIN, baseSize);
            choiceFont = outfit.deriveFont(Font.PLAIN, 15f);
            resetFont = outfit.deriveFont(Font.PLAIN, 13.5f);
        } else {
            dialogueFont = new Font("SansSerif", Font.PLAIN, (int) baseSize);
            choiceFont = new Font("SansSerif", Font.PLAIN, 15);
            resetFont = new Font("SansSerif", Font.PLAIN, 13);
        }

        // Character names use SemiBold (weight 600, matching web's font-weight: 600)
        if (outfitSemiBold != null) {
            nameBoldFont = outfitSemiBold.deriveFont(Font.PLAIN, baseSize);
        } else if (outfit != null) {
            nameBoldFont = outfit.deriveFont(Font.BOLD, baseSize);
        } else {
            nameBoldFont = new Font("SansSerif", Font.BOLD, (int) baseSize);
        }
    }

    private static Font loadFont(String path) {
        try (InputStream is = new FileInputStream(path)) {
            Font font = Font.createFont(Font.TRUETYPE_FONT, is);
            GraphicsEnvironment.getLocalGraphicsEnvironment().registerFont(font);
            return font;
        } catch (Exception e) {
            return null;
        }
    }
}
