/* =========================================================
   Cue · site behaviour
   No dependencies, no network, no tracking.
   ========================================================= */

(function () {
  "use strict";

  var root = document.documentElement;
  var $ = function (selector, context) {
    return (context || document).querySelector(selector);
  };
  var $$ = function (selector, context) {
    return Array.prototype.slice.call((context || document).querySelectorAll(selector));
  };
  var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  var motionOK = !reducedMotion.matches;

  var LAMP_TITLES = { daylight: "Daylight", evening: "Evening", night: "Night" };
  var THEME_COLORS = { daylight: "#ECE9E4", evening: "#E8DFD4", night: "#14110E" };

  /* ---------------------------------------------------------
     Storage, safely
     --------------------------------------------------------- */

  function readStore(key, fallback) {
    try {
      var value = localStorage.getItem(key);
      return value === null ? fallback : value;
    } catch (error) {
      return fallback;
    }
  }

  function writeStore(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (error) {
      /* A private window can refuse storage. The page still works. */
    }
  }

  /* ---------------------------------------------------------
     Lamp
     --------------------------------------------------------- */

  function scheduleFor(date) {
    var hour = date.getHours();
    if (hour >= 7 && hour < 17) return "daylight";
    if (hour >= 17 && hour < 21) return "evening";
    return "night";
  }

  var lampChoice = root.dataset.lampChoice || readStore("cue.lamp", "auto");
  if (["auto", "daylight", "evening", "night"].indexOf(lampChoice) === -1) lampChoice = "auto";
  var currentLamp = root.dataset.lamp || (lampChoice === "auto" ? scheduleFor(new Date()) : lampChoice);
  var lit = root.dataset.lit !== "off";

  var lampLive = document.createElement("p");
  lampLive.className = "sr-only";
  lampLive.setAttribute("role", "status");
  lampLive.setAttribute("aria-live", "polite");
  document.body.appendChild(lampLive);

  var lampTrigger = $("[data-lamp-picker] .lamp-trigger");
  var lampMenu = $("#lamp-menu");
  var lampPicker = $("[data-lamp-picker]");
  var lampOptions = $$(".lamp-option[data-lamp-choice]");
  var pageLampButtons = $$("[data-page-lamp]");
  var litToggles = $$("[data-lit-toggle]");
  var sceneLabel = $("[data-scene-label]");

  function lampLabel() {
    return lampChoice === "auto" ? "Auto · " + LAMP_TITLES[currentLamp] : LAMP_TITLES[currentLamp];
  }

  function updateThemeColor() {
    var meta = $('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", THEME_COLORS[currentLamp]);
  }

  function syncLampUI() {
    var label = lampLabel();
    $$("[data-lamp-label]").forEach(function (node) {
      node.textContent = label;
    });
    if (lampTrigger) {
      lampTrigger.setAttribute("aria-label", "Lamp: " + label + ". Change the lamp.");
    }
    lampOptions.forEach(function (button) {
      var checked =
        (button.getAttribute("data-lamp-choice") === "auto" && lampChoice === "auto") ||
        (button.getAttribute("data-lamp-choice") === currentLamp && lampChoice !== "auto");
      button.setAttribute("aria-checked", checked ? "true" : "false");
    });
    pageLampButtons.forEach(function (button) {
      var value = button.getAttribute("data-page-lamp");
      var pressed = value === "auto" ? lampChoice === "auto" : lampChoice === value;
      button.setAttribute("aria-pressed", pressed ? "true" : "false");
    });
    $$(".status-lamp").forEach(function (node) {
      node.textContent = LAMP_TITLES[currentLamp];
    });
    syncLitUI();
    updateSceneLabel();
  }

  function syncLitUI() {
    litToggles.forEach(function (button) {
      button.setAttribute("aria-checked", lit ? "true" : "false");
    });
    $$("[data-lit-label]").forEach(function (node) {
      node.textContent = lit ? "Lamp on" : "Lamp off";
    });
    if (lampMenu) {
      var litButton = $("[data-lit-toggle]", lampMenu);
      if (litButton) litButton.setAttribute("aria-label", lit ? "Turn the lamp off" : "Turn the lamp on");
    }
  }

  function updateSceneLabel() {
    if (!sceneLabel) return;
    var time;
    try {
      time = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(new Date());
    } catch (error) {
      time = "";
    }
    sceneLabel.textContent = LAMP_TITLES[currentLamp] + (time ? " · " + time : "");
  }

  function setLamp(lamp, choice, options) {
    options = options || {};
    currentLamp = lamp;
    if (choice) lampChoice = choice;
    root.dataset.lamp = lamp;
    root.dataset.lampChoice = lampChoice;
    if (options.persist !== false) writeStore("cue.lamp", lampChoice);
    if (options.light !== false && !lit) {
      lit = true;
      root.dataset.lit = "on";
      writeStore("cue.lit", "on");
    }
    updateThemeColor();
    syncLampUI();
    if (options.announce) {
      lampLive.textContent = "Lamp: " + lampLabel() + (lit ? "" : ", lamp off");
    }
  }

  function chooseLamp(value, announce) {
    if (value === "auto") {
      setLamp(scheduleFor(new Date()), "auto", { announce: announce });
    } else {
      setLamp(value, value, { announce: announce });
    }
  }

  function toggleLit(force) {
    lit = typeof force === "boolean" ? force : !lit;
    root.dataset.lit = lit ? "on" : "off";
    writeStore("cue.lit", lit ? "on" : "off");
    syncLitUI();
    lampLive.textContent = lit ? "Lamp on" : "Lamp off";
  }

  updateThemeColor();
  syncLampUI();

  lampOptions.forEach(function (option) {
    option.addEventListener("click", function () {
      chooseLamp(option.getAttribute("data-lamp-choice"), true);
      closeLampMenu(true);
    });
  });

  pageLampButtons.forEach(function (button) {
    button.addEventListener("click", function () {
      chooseLamp(button.getAttribute("data-page-lamp"), true);
    });
  });

  litToggles.forEach(function (button) {
    button.addEventListener("click", function () {
      toggleLit();
    });
  });

  /* Lamp menu: open, close, keyboard. */
  function openLampMenu() {
    if (!lampMenu || !lampTrigger) return;
    closeMobileMenu(false);
    lampMenu.hidden = false;
    lampTrigger.setAttribute("aria-expanded", "true");
    var selected = lampOptions.find(function (option) {
      return option.getAttribute("aria-checked") === "true";
    }) || lampOptions[0];
    window.requestAnimationFrame(function () {
      if (selected) selected.focus();
    });
  }

  function closeLampMenu(returnFocus) {
    if (!lampMenu || lampMenu.hidden) return;
    lampMenu.hidden = true;
    if (lampTrigger) {
      lampTrigger.setAttribute("aria-expanded", "false");
      if (returnFocus) lampTrigger.focus();
    }
  }

  if (lampTrigger && lampMenu) {
    lampTrigger.addEventListener("click", function () {
      if (lampMenu.hidden) openLampMenu();
      else closeLampMenu(true);
    });

    lampMenu.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        event.preventDefault();
        closeLampMenu(true);
        return;
      }
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        var index = lampOptions.indexOf(document.activeElement);
        if (index === -1) index = 0;
        var step = event.key === "ArrowDown" ? 1 : -1;
        index = (index + step + lampOptions.length) % lampOptions.length;
        lampOptions[index].focus();
      }
    });

    document.addEventListener("pointerdown", function (event) {
      if (lampMenu.hidden) return;
      if (lampPicker && !lampPicker.contains(event.target)) closeLampMenu(false);
    });
  }

  if (lampPicker) {
    lampPicker.addEventListener("focusout", function (event) {
      if (lampMenu.hidden) return;
      if (event.relatedTarget && lampPicker.contains(event.relatedTarget)) return;
      window.setTimeout(function () {
        if (!lampMenu.hidden && !lampPicker.contains(document.activeElement)) closeLampMenu(false);
      }, 10);
    });
  }

  /* Auto follows the clock. */
  window.setInterval(function () {
    updateSceneLabel();
    if (lampChoice !== "auto") return;
    var next = scheduleFor(new Date());
    if (next !== currentLamp) setLamp(next, "auto", { persist: false });
  }, 60000);

  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && lampChoice === "auto") {
      var next = scheduleFor(new Date());
      if (next !== currentLamp) setLamp(next, "auto", { persist: false });
    }
  });

  /* ---------------------------------------------------------
     Mobile menu
     --------------------------------------------------------- */

  var navToggle = $(".nav-toggle");
  var mobileMenu = $("#mobile-menu");

  function openMobileMenu() {
    if (!mobileMenu || !navToggle) return;
    closeLampMenu(false);
    mobileMenu.hidden = false;
    navToggle.setAttribute("aria-expanded", "true");
    document.body.classList.add("menu-open");
    var first = $("a", mobileMenu);
    window.requestAnimationFrame(function () {
      if (first) first.focus();
    });
  }

  function closeMobileMenu(returnFocus) {
    if (!mobileMenu || mobileMenu.hidden) return;
    mobileMenu.hidden = true;
    document.body.classList.remove("menu-open");
    if (navToggle) {
      navToggle.setAttribute("aria-expanded", "false");
      if (returnFocus) navToggle.focus();
    }
  }

  if (navToggle && mobileMenu) {
    navToggle.addEventListener("click", function () {
      if (mobileMenu.hidden) openMobileMenu();
      else closeMobileMenu(true);
    });

    $$("a", mobileMenu).forEach(function (link) {
      link.addEventListener("click", function () {
        closeMobileMenu(false);
      });
    });

    mobileMenu.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        event.preventDefault();
        closeMobileMenu(true);
      }
    });

    document.addEventListener("pointerdown", function (event) {
      if (mobileMenu.hidden) return;
      if (!event.target.closest(".site-header")) closeMobileMenu(false);
    });

    var desktopQuery = window.matchMedia("(min-width: 941px)");
    var onDesktop = function (event) {
      if (event.matches) closeMobileMenu(false);
    };
    if (desktopQuery.addEventListener) desktopQuery.addEventListener("change", onDesktop);
    else if (desktopQuery.addListener) desktopQuery.addListener(onDesktop);
  }

  /* ---------------------------------------------------------
     Header on scroll + reveal
     --------------------------------------------------------- */

  var header = $(".site-header");
  if (header) {
    var lastScrolled = false;
    var onScroll = function () {
      var scrolled = window.scrollY > 8;
      if (scrolled !== lastScrolled) {
        header.classList.toggle("is-scrolled", scrolled);
        lastScrolled = scrolled;
      }
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  var reveals = $$(".reveal");
  if (reveals.length) {
    if (!motionOK || !("IntersectionObserver" in window)) {
      reveals.forEach(function (node) {
        node.classList.add("is-in");
      });
    } else {
      var revealObserver = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-in");
              revealObserver.unobserve(entry.target);
            }
          });
        },
        { rootMargin: "0px 0px -8% 0px", threshold: 0.06 }
      );
      reveals.forEach(function (node) {
        revealObserver.observe(node);
      });
    }
  }

  /* ---------------------------------------------------------
     Hero typing
     --------------------------------------------------------- */

  function typeText(node, text, options) {
    options = options || {};
    var characters = Array.from(text);
    var index = 0;
    var speed = options.speed || 55;
    node.textContent = "";
    if (options.caret) options.caret.classList.remove("is-done");
    function tick() {
      if (index >= characters.length) {
        if (options.caret) options.caret.classList.add("is-done");
        if (options.onDone) options.onDone();
        return;
      }
      node.textContent += characters[index];
      index += 1;
      window.setTimeout(tick, speed);
    }
    window.setTimeout(tick, options.delay || 0);
  }

  var typedWord = $("[data-typed]");
  var typedLine = $(".typed-line");
  if (typedWord && typedLine && motionOK) {
    var fullHeadline = typedWord.textContent;
    window.setTimeout(function () {
      typeText(typedWord, fullHeadline, { speed: 52, caret: typedLine });
    }, 520);
  } else if (typedWord && typedLine) {
    typedWord.textContent = typedWord.textContent;
    typedLine.classList.add("is-done");
  }

  var mockType = $("[data-mock-type]");
  if (mockType && motionOK) {
    var mockText = mockType.textContent;
    mockType.textContent = "";
    window.setTimeout(function () {
      typeText(mockType, mockText, { speed: 34 });
    }, 1500);
  }

  if (reducedMotion.addEventListener) {
    reducedMotion.addEventListener("change", function (event) {
      motionOK = !event.matches;
    });
  }

  /* ---------------------------------------------------------
     Demo editor
     --------------------------------------------------------- */

  var editor = $("#editor");
  var paper = $("#script-page");
  var demoStage = $(".paper-stage");
  var chooserLayer = $("#chooser-layer");
  var demoMeta = $("#demo-meta");
  var demoStatus = $("#demo-status");
  var demoReset = $("#demo-reset");

  if (editor && paper && demoStage && chooserLayer) {
    var TYPE_INFO = {
      scene: { name: "Scene heading", aria: "Scene heading" },
      action: { name: "Action", aria: "Action line" },
      character: { name: "Character", aria: "Character line" },
      paren: { name: "Parenthetical", aria: "Parenthetical" },
      dialogue: { name: "Dialogue", aria: "Dialogue line" },
      transition: { name: "Transition", aria: "Transition" },
      new: { name: "New line", aria: "New line" }
    };
    var CHOICES = [
      { type: "action", label: "Action" },
      { type: "character", label: "Character" },
      { type: "scene", label: "Scene" },
      { type: "transition", label: "Transition" }
    ];
    var CYCLE = ["action", "character", "dialogue", "paren", "scene", "transition"];
    var TIMES = ["DAY", "NIGHT", "EVENING", "MORNING", "CONTINUOUS", "LATER", "MOMENTS LATER", "DUSK", "DAWN"];
    var CHAR_COLORS = ["#D0664A", "#6C9A70", "#C99A3E", "#A8607C", "#4E9396", "#B8744C", "#8A8B4A", "#C47489"];
    var INITIAL = [
      ["scene", "INT. KITCHEN TABLE - 2 AM"],
      ["action", "A laptop glows. MAYA (30s) stares at a blinking cursor. Her tea went cold an hour ago."],
      ["character", "MAYA"],
      ["paren", "(to the cat)"],
      ["dialogue", "One page. Then bed."],
      ["action", "The cat does not believe her."],
      ["new", ""]
    ];

    var lineSeq = 0;
    function makeLine(type, text) {
      lineSeq += 1;
      return { id: "l" + lineSeq, type: type, text: text };
    }

    var lines = INITIAL.map(function (item) {
      return makeLine(item[0], item[1]);
    });
    var focusId = null;
    var chooser = { open: false, index: 0, id: null };
    var timeMenu = { open: false, index: 0, id: null };
    var ghost = null;
    var composing = false;

    function lineById(id) {
      for (var i = 0; i < lines.length; i += 1) {
        if (lines[i].id === id) return lines[i];
      }
      return null;
    }

    function indexById(id) {
      for (var i = 0; i < lines.length; i += 1) {
        if (lines[i].id === id) return i;
      }
      return -1;
    }

    function focusedLine() {
      return focusId ? lineById(focusId) : null;
    }

    function rowFor(id) {
      return $('.el[data-id="' + id + '"]', editor);
    }

    function textareaFor(id) {
      var row = rowFor(id);
      return row ? $("textarea", row) : null;
    }

    function isUpper(text) {
      return /[A-Za-z]/.test(text) && text === text.toUpperCase();
    }

    function isScenePrefix(text) {
      return /^(INT|EXT|INT\.\/EXT|I\/E)[.\s]/i.test(text);
    }

    function isTransition(text) {
      return isUpper(text) && /(TO:|FADE OUT\.|FADE IN\.|FADE TO BLACK\.)$/.test(text.trim());
    }

    function isCharacterLike(text) {
      var trimmed = text.trim();
      return (
        isUpper(trimmed) &&
        /[A-Z]/.test(trimmed) &&
        trimmed.replace(/[^A-Z]/g, "").length >= 2 &&
        trimmed.length <= 48 &&
        !isScenePrefix(trimmed) &&
        !isTransition(trimmed)
      );
    }

    function inferType(text) {
      var trimmed = text.trim();
      if (isScenePrefix(trimmed)) return "scene";
      if (isTransition(trimmed)) return "transition";
      if (isCharacterLike(trimmed)) return "character";
      return "action";
    }

    function placeKey(text) {
      return text
        .replace(/\(.*$/, "")
        .replace(/\s+[-–—]\s+.*$/, "")
        .replace(/^(INT|EXT|INT\.\/EXT|I\/E)[.\s]+/i, "")
        .trim()
        .toUpperCase();
    }

    function scenePlace(text) {
      if (!isScenePrefix(text)) return "";
      return text
        .replace(/^(INT|EXT|INT\.\/EXT|I\/E)[.\s]+/i, "")
        .replace(/\(.*$/, "")
        .replace(/\s+[-–—]\s+.*$/, "")
        .trim();
    }

    function cueName(text) {
      return text.replace(/\(.*$/, "").trim().toUpperCase();
    }

    function derived() {
      var result = { names: [], places: [], colors: {}, sceneCount: 0, characterCount: 0 };
      var speaker = null;
      lines.forEach(function (line) {
        if (line.type === "scene" && line.text.trim()) {
          result.sceneCount += 1;
          var place = placeKey(line.text);
          if (place && result.places.indexOf(place) === -1) result.places.push(place);
        }
        if (line.type === "character" && line.text.trim()) {
          speaker = cueName(line.text);
          if (result.colors[speaker] === undefined) {
            result.colors[speaker] = CHAR_COLORS[result.names.length % CHAR_COLORS.length];
            result.names.push(speaker);
          }
          result.characterCount = result.names.length;
        } else if (line.type !== "paren" && line.type !== "dialogue") {
          speaker = null;
        }
      });
      result.speakerFor = function (line) {
        /* The rendering pass does its own walk so the bar survives across
           parenthetical and dialogue lines. */
        return null;
      };
      return result;
    }

    function placeholderFor(line, index) {
      if (line.type === "scene") {
        return index === 0 ? "Type I for INT. or E for EXT." : "INT. or EXT.";
      }
      if (line.type === "character") return "NAME";
      if (line.type === "paren") return "(beat)";
      if (line.type === "dialogue") return "What they say…";
      if (line.type === "transition") return "CUT TO:";
      if (line.type === "action") return "What happens…";
      return index === lines.length - 1 ? "Type, or choose a format…" : "What happens…";
    }

    function setStatus(text) {
      if (demoStatus && demoStatus.textContent !== text) demoStatus.textContent = text;
    }

    function describe(line) {
      switch (line.type) {
        case "scene":
          return "Scene heading. Type the place, then a dash for the time.";
        case "character":
          return "Character. Enter starts their dialogue.";
        case "dialogue":
          return "Dialogue. Enter offers the next line.";
        case "paren":
          return "Parenthetical. Enter goes back to dialogue.";
        case "transition":
          return "Transition. Enter offers the next line.";
        case "action":
          return "Action. Enter offers what comes next. Tab changes the element.";
        default:
          return "Choose a format, or just start typing. Tab cycles the element.";
      }
    }

    function setRowType(row, line) {
      if (!row) return;
      row.className = "el el--" + line.type;
      var ta = $("textarea", row);
      if (!ta) return;
      ta.setAttribute("aria-label", TYPE_INFO[line.type].aria + ", line " + (indexById(line.id) + 1));
      ta.setAttribute("placeholder", placeholderFor(line, indexById(line.id)));
      ta.spellcheck = line.type === "action" || line.type === "dialogue";
      ta.setAttribute("autocapitalize", line.type === "scene" || line.type === "character" || line.type === "transition" ? "characters" : "sentences");
    }

    function autosize(ta) {
      if (!ta) return;
      ta.style.height = "0px";
      ta.style.height = ta.scrollHeight + "px";
    }

    function autosizeAll() {
      $$("textarea", editor).forEach(autosize);
    }

    function decorate() {
      var speaker = null;
      var sceneNumber = 0;
      var colorIndex = 0;
      var colors = {};
      lines.forEach(function (line, index) {
        var row = rowFor(line.id);
        if (!row) return;
        if (line.type === "scene" && line.text.trim()) {
          sceneNumber += 1;
          row.setAttribute("data-scene-number", sceneNumber);
        } else {
          row.removeAttribute("data-scene-number");
        }
        if (line.type === "character" && line.text.trim()) {
          speaker = cueName(line.text);
          if (colors[speaker] === undefined) {
            colors[speaker] = CHAR_COLORS[colorIndex % CHAR_COLORS.length];
            colorIndex += 1;
          }
        } else if (line.type !== "paren" && line.type !== "dialogue") {
          speaker = null;
        }
        if (speaker && (line.type === "character" || line.type === "paren" || line.type === "dialogue")) {
          row.classList.add("is-speech");
          row.style.setProperty("--c", colors[speaker]);
        } else {
          row.classList.remove("is-speech");
          row.style.removeProperty("--c");
        }
        row.classList.toggle("is-empty", !line.text);
      });

      var info = derived();
      if (demoMeta) {
        if (!info.sceneCount && !info.characterCount) {
          demoMeta.textContent = "Blank page";
        } else {
          demoMeta.textContent =
            info.sceneCount +
            (info.sceneCount === 1 ? " scene" : " scenes") +
            " · " +
            info.characterCount +
            (info.characterCount === 1 ? " character" : " characters");
        }
      }
    }

    function buildRow(line, index) {
      var row = document.createElement("div");
      row.className = "el el--" + line.type;
      row.setAttribute("data-id", line.id);
      if (!line.text) row.classList.add("is-empty");

      var field = document.createElement("div");
      field.className = "el-field";

      var mirror = document.createElement("span");
      mirror.className = "ghost-mirror";
      mirror.setAttribute("aria-hidden", "true");
      var typed = document.createElement("span");
      typed.className = "ghost-typed";
      var suffix = document.createElement("span");
      suffix.className = "ghost-suffix";
      mirror.appendChild(typed);
      mirror.appendChild(suffix);

      var ta = document.createElement("textarea");
      ta.rows = 1;
      ta.value = line.text;
      ta.id = "line-" + line.id;
      ta.setAttribute("aria-label", TYPE_INFO[line.type].aria + ", line " + (index + 1));
      ta.setAttribute("aria-describedby", "demo-instructions");
      ta.setAttribute("placeholder", placeholderFor(line, index));
      ta.setAttribute("enterkeyhint", "next");
      ta.setAttribute("autocomplete", "off");
      ta.setAttribute("autocorrect", "off");
      ta.setAttribute("spellcheck", line.type === "action" || line.type === "dialogue" ? "true" : "false");
      ta.setAttribute(
        "autocapitalize",
        line.type === "scene" || line.type === "character" || line.type === "transition" ? "characters" : "sentences"
      );

      field.appendChild(mirror);
      field.appendChild(ta);
      row.appendChild(field);
      return row;
    }

    function render(options) {
      options = options || {};
      var fragment = document.createDocumentFragment();
      lines.forEach(function (line, index) {
        fragment.appendChild(buildRow(line, index));
      });
      editor.replaceChildren(fragment);
      autosizeAll();
      decorate();

      var nextFocus = options.focusId || focusId;
      if (nextFocus && lineById(nextFocus)) {
        focusId = nextFocus;
        var ta = textareaFor(nextFocus);
        if (ta) {
          ta.focus({ preventScroll: true });
          var caret = typeof options.caret === "number" ? options.caret : lineById(nextFocus).text.length;
          try {
            ta.setSelectionRange(caret, caret);
          } catch (error) {}
          autosize(ta);
        }
      }

      updateGhost();
      if (options.openChooser) {
        openChooser();
      } else if (chooser.open) {
        renderChooser();
      }
      if (timeMenu.open) renderTimeMenu();
    }

    function currentTextarea() {
      return focusId ? textareaFor(focusId) : null;
    }

    function focusLine(id, caret) {
      focusId = id;
      var ta = textareaFor(id);
      if (!ta) return;
      ta.focus({ preventScroll: true });
      if (typeof caret === "number") {
        try {
          ta.setSelectionRange(caret, caret);
        } catch (error) {}
      }
      autosize(ta);
      updateGhost();
    }

    /* Ghost suggestions, made from words already on the page. */
    function calculateGhost() {
      var line = focusedLine();
      if (!line) return null;
      var ta = currentTextarea();
      if (!ta) return null;
      if (ta.selectionStart !== ta.selectionEnd) return null;
      if (ta.selectionStart !== line.text.length) return null;
      var text = line.text;
      if (!text) return null;

      var info = derived();
      if ((line.type === "new" || line.type === "character") && isUpper(text) && text.indexOf("(") === -1) {
        var upper = text.toUpperCase();
        for (var i = 0; i < info.names.length; i += 1) {
          var name = info.names[i];
          if (name !== upper && name.indexOf(upper) === 0) {
            return { suffix: name.slice(upper.length), kind: "character", full: name };
          }
        }
      }

      if (line.type === "new" || line.type === "action") {
        var value = text.toUpperCase();
        if (text === value) {
          if (["I", "IN", "INT"].indexOf(value) !== -1) {
            return { suffix: "INT. ".slice(text.length), kind: "scene", full: "INT. " };
          }
          if (["E", "EX", "EXT"].indexOf(value) !== -1) {
            return { suffix: "EXT. ".slice(text.length), kind: "scene", full: "EXT. " };
          }
        }
      }

      if (line.type === "scene" && scenePlace(text) && !/[–—-]\s*$/.test(text)) {
        var place = scenePlace(text).toUpperCase();
        var candidates = info.places.filter(function (candidate) {
          return candidate !== place && candidate.indexOf(place) === 0;
        });
        if (candidates.length) {
          return { suffix: candidates[0].slice(place.length), kind: "place", full: candidates[0] };
        }
      }
      return null;
    }

    function updateGhost() {
      ghost = calculateGhost();
      var line = focusedLine();
      if (!line) return;
      var row = rowFor(line.id);
      if (!row) return;
      var mirror = $(".ghost-mirror", row);
      if (!mirror) return;
      var typed = $(".ghost-typed", mirror);
      var suffix = $(".ghost-suffix", mirror);
      typed.textContent = line.text;
      suffix.textContent = ghost ? ghost.suffix : "";
      if (ghost) {
        setStatus(
          "Suggestion: " + ghost.full + ". Press the right arrow to accept, or keep typing."
        );
      }
    }

    function acceptGhost() {
      var line = focusedLine();
      if (!line || !ghost) return;
      line.text = (line.text + ghost.suffix).toUpperCase();
      if (ghost.kind === "character") line.type = "character";
      if (ghost.kind === "scene") line.type = "scene";
      var ta = currentTextarea();
      if (ta) {
        ta.value = line.text;
        setRowType(rowFor(line.id), line);
        ta.setSelectionRange(line.text.length, line.text.length);
        autosize(ta);
      }
      ghost = null;
      decorate();
      updateGhost();
      setStatus("Suggestion taken.");
    }

    function syncFocusedLine() {
      var row = focusId ? rowFor(focusId) : null;
      if (!row) return;
      var ta = $("textarea", row);
      if (!ta) return;
      var line = lineById(focusId);
      if (!line) return;
      autosize(ta);
      var mirror = $(".ghost-mirror", row);
      if (mirror) {
        $(".ghost-typed", mirror).textContent = line.text;
        $(".ghost-suffix", mirror).textContent = ghost ? ghost.suffix : "";
      }
    }

    function closeChooser() {
      var wasOpen = chooser.open;
      chooser.open = false;
      chooser.id = null;
      if (wasOpen && !timeMenu.open) chooserLayer.replaceChildren();
    }

    function closeTimeMenu() {
      var wasOpen = timeMenu.open;
      timeMenu.open = false;
      timeMenu.id = null;
      if (wasOpen && !chooser.open) chooserLayer.replaceChildren();
    }

    function renderChooser() {
      if (!chooser.open) return;
      var line = focusedLine();
      if (!line || line.type !== "new" || line.text) {
        closeChooser();
        return;
      }
      var menu = document.createElement("div");
      menu.className = "element-chooser";
      menu.setAttribute("role", "listbox");
      menu.setAttribute("aria-label", "Next element type");

      var label = document.createElement("p");
      label.className = "chooser-label";
      label.textContent = "Next element";
      menu.appendChild(label);

      var options = document.createElement("div");
      options.className = "chooser-options";
      CHOICES.forEach(function (choice, index) {
        var button = document.createElement("button");
        button.type = "button";
        button.className = "chooser-option";
        button.setAttribute("role", "option");
        button.setAttribute("aria-selected", index === chooser.index ? "true" : "false");
        button.setAttribute("tabindex", "-1");
        button.textContent = choice.label;
        button.addEventListener("click", function () {
          applyChoice(index);
        });
        options.appendChild(button);
      });
      menu.appendChild(options);

      var foot = document.createElement("p");
      foot.className = "chooser-foot";
      foot.textContent = "↑ ↓ choose · Enter takes it · Tab cycles";
      menu.appendChild(foot);

      chooserLayer.replaceChildren(menu);
      positionPopover(menu);
      setStatus("Choose the next element, or just start typing.");
    }

    function openChooser(index) {
      var line = focusedLine();
      if (!line || line.type !== "new" || line.text) {
        closeChooser();
        return;
      }
      chooser.open = true;
      chooser.id = line.id;
      if (typeof index === "number") chooser.index = index;
      renderChooser();
    }

    function moveChooser(step) {
      chooser.index = (chooser.index + step + CHOICES.length) % CHOICES.length;
      renderChooser();
      var buttons = $$(".chooser-option", chooserLayer);
      if (buttons[chooser.index]) {
        buttons[chooser.index].setAttribute("aria-selected", "true");
      }
      setStatus(CHOICES[chooser.index].label + " selected. Enter takes it.");
    }

    function applyChoice(index) {
      var line = focusedLine();
      if (!line) return;
      chooser.index = index;
      line.type = CHOICES[index].type;
      closeChooser();
      setRowType(rowFor(line.id), line);
      decorate();
      updateGhost();
      var ta = currentTextarea();
      if (ta) ta.focus({ preventScroll: true });
      setStatus(CHOICES[index].label + ". Type the line, or Enter for the next.");
    }

    function renderTimeMenu() {
      if (!timeMenu.open) return;
      var line = focusedLine();
      if (!line || line.type !== "scene") {
        closeTimeMenu();
        return;
      }
      var menu = document.createElement("div");
      menu.className = "time-menu";
      menu.setAttribute("role", "listbox");
      menu.setAttribute("aria-label", "Time of day");

      var label = document.createElement("p");
      label.className = "time-title";
      label.textContent = "Time of day";
      menu.appendChild(label);

      TIMES.forEach(function (time, index) {
        var button = document.createElement("button");
        button.type = "button";
        button.className = "time-option";
        button.setAttribute("role", "option");
        button.setAttribute("aria-selected", index === timeMenu.index ? "true" : "false");
        button.setAttribute("tabindex", "-1");
        var left = document.createElement("span");
        left.textContent = time;
        var right = document.createElement("span");
        right.textContent = index === 0 ? "↵" : "";
        button.appendChild(left);
        button.appendChild(right);
        button.addEventListener("click", function () {
          chooseTime(index, true);
        });
        menu.appendChild(button);
      });

      chooserLayer.replaceChildren(menu);
      positionPopover(menu);
      setStatus("Choose the time of day. Enter takes the highlighted one.");
    }

    function openTimeMenu() {
      var line = focusedLine();
      if (!line || line.type !== "scene") return;
      timeMenu.open = true;
      timeMenu.id = line.id;
      timeMenu.index = 0;
      renderTimeMenu();
    }

    function moveTime(step) {
      timeMenu.index = (timeMenu.index + step + TIMES.length) % TIMES.length;
      renderTimeMenu();
      setStatus(TIMES[timeMenu.index] + " selected. Enter takes it.");
    }

    function chooseTime(index, advance) {
      var line = focusedLine();
      if (!line) return;
      var base = line.text.replace(/\s+[-–—]\s*$/, "").replace(/\s+[-–—]\s*[A-Z ]+$/, "").trimEnd();
      line.text = base + " - " + TIMES[index];
      line.type = "scene";
      closeTimeMenu();
      if (advance) {
        var next = makeLine("action", "");
        lines.splice(indexById(line.id) + 1, 0, next);
        render({ focusId: next.id, caret: 0 });
        setStatus("Scene set to " + TIMES[index] + ".");
      } else {
        render({ focusId: line.id, caret: line.text.length });
        setStatus("Scene set to " + TIMES[index] + ".");
      }
    }

    function positionPopover(popover) {
      var ta = currentTextarea();
      if (!ta) return;
      var row = ta.closest(".el");
      var layerBox = chooserLayer.getBoundingClientRect();
      var rowBox = row.getBoundingClientRect();
      var width = popover.offsetWidth || 196;
      var height = popover.offsetHeight || 170;
      var left = rowBox.left - layerBox.left + Math.min(44, rowBox.width * 0.15);
      left = Math.max(8, Math.min(left, layerBox.width - width - 8));
      var top = rowBox.bottom - layerBox.top + 7;
      if (top + height > layerBox.height - 8) {
        top = rowBox.top - layerBox.top - height - 7;
      }
      top = Math.max(6, top);
      popover.style.left = left + "px";
      popover.style.top = top + "px";
    }

    function setType(line, type) {
      line.type = type;
      var row = rowFor(line.id);
      setRowType(row, line);
      var ta = row ? $("textarea", row) : null;
      if (ta) {
        if (type === "scene" || type === "character" || type === "transition") {
          var upper = line.text.toUpperCase();
          if (upper !== line.text) {
            line.text = upper;
            ta.value = upper;
            ta.setSelectionRange(upper.length, upper.length);
          }
        }
        autosize(ta);
      }
      decorate();
      updateGhost();
      if (chooser.open) {
        openChooser(CHOICES.findIndex(function (choice) { return choice.type === line.type; }));
      }
    }

    function cycleType(direction) {
      var line = focusedLine();
      if (!line) return;
      var base = line.type === "new" ? inferType(line.text) : line.type;
      var index = CYCLE.indexOf(base);
      if (index === -1) index = 0;
      index = (index + direction + CYCLE.length) % CYCLE.length;
      setType(line, CYCLE[index]);
      setStatus(TYPE_INFO[line.type].name + " selected. Tab for the next.");
    }

    function closeMenusForTyping() {
      if (chooser.open) closeChooser();
      if (timeMenu.open) closeTimeMenu();
    }

    function handleInput(event) {
      if (composing) return;
      var ta = event.target;
      if (!ta || ta.tagName !== "TEXTAREA") return;
      var row = ta.closest(".el");
      if (!row) return;
      var line = lineById(row.getAttribute("data-id"));
      if (!line) return;

      var oldText = line.text;
      var text = ta.value.replace(/\r/g, "").replace(/\n/g, " ");
      var type = line.type;
      var caret = ta.selectionStart;
      var changedLength = false;

      if (type === "scene" && oldText === "" && text.length === 1) {
        if (text.toLowerCase() === "i") {
          text = "INT. ";
          caret = text.length;
          changedLength = true;
        } else if (text.toLowerCase() === "e") {
          text = "EXT. ";
          caret = text.length;
          changedLength = true;
        }
      }

      if (type === "scene" && /^(INT|EXT)\. \/$/i.test(text)) {
        var prefix = text.slice(0, 4);
        text = prefix + "/" + (text.charAt(0).toUpperCase() === "I" ? "EXT. " : "INT. ");
        caret = text.length;
        changedLength = true;
      }

      if ((type === "new" || type === "action") && isScenePrefix(text)) {
        type = "scene";
      }

      if (type === "new" && isTransition(text)) {
        type = "transition";
      }

      if (type === "scene" || type === "character" || type === "transition") {
        var upper = text.toUpperCase();
        if (upper !== text) {
          text = upper;
          caret = Math.min(caret, text.length);
          changedLength = true;
        }
      }

      line.text = text;
      if (line.type !== type) {
        line.type = type;
        setRowType(row, line);
      }

      if (changedLength || ta.value !== text) {
        ta.value = text;
        try {
          ta.setSelectionRange(caret, caret);
        } catch (error) {}
      }

      closeMenusForTyping();
      autosize(ta);
      decorate();
      updateGhost();

      if (line.type === "scene" && /[–—-]\s*$/.test(text) && scenePlace(text)) {
        openTimeMenu();
      } else {
        setStatus(describe(line));
      }
    }

    function handleEnter(event) {
      var line = focusedLine();
      var ta = currentTextarea();
      if (!line || !ta) return;
      var start = ta.selectionStart;
      var end = ta.selectionEnd;

      if (!line.text.trim()) {
        if (line.type === "new") {
          event.preventDefault();
          setStatus("Type something, or press Tab to choose an element.");
          return;
        }
      }

      if (line.type === "new") {
        var inferred = inferType(line.text);
        line.type = inferred;
        setRowType(rowFor(line.id), line);
        if (inferred === "scene" && /[–—-]\s*$/.test(line.text) && scenePlace(line.text)) {
          event.preventDefault();
          openTimeMenu();
          return;
        }
      }

      if (line.type === "action" && isCharacterLike(line.text) && start === line.text.length) {
        line.type = "character";
        setRowType(rowFor(line.id), line);
      } else if (line.type === "action" && isTransition(line.text) && start === line.text.length) {
        line.type = "transition";
        setRowType(rowFor(line.id), line);
      }

      if (line.type === "scene" && /[–—-]\s*$/.test(line.text) && scenePlace(line.text)) {
        event.preventDefault();
        openTimeMenu();
        return;
      }

      event.preventDefault();

      var before = line.text.slice(0, start);
      var after = line.text.slice(end);
      if (line.type === "paren") {
        before = line.text.trim();
        after = "";
      }

      var nextType;
      if (line.type === "scene") nextType = "action";
      else if (line.type === "character") nextType = "dialogue";
      else if (line.type === "paren") nextType = "dialogue";
      else if (line.type === "transition") nextType = "new";
      else if (after) nextType = line.type;
      else nextType = "new";

      line.text = before;
      var next = makeLine(nextType, after);
      lines.splice(indexById(line.id) + 1, 0, next);

      render({
        focusId: next.id,
        caret: after.length,
        openChooser: nextType === "new"
      });

      if (nextType === "new") {
        setStatus("Choose the next element, or just start typing.");
      } else {
        setStatus(describe({ type: nextType, text: after }));
      }
      closeTimeMenu();
    }

    function mergeBackspace() {
      var line = focusedLine();
      var ta = currentTextarea();
      if (!line || !ta) return false;
      if (ta.selectionStart !== 0 || ta.selectionEnd !== 0) return false;
      var index = indexById(line.id);
      if (index === 0) return false;
      var previous = lines[index - 1];
      var previousText = previous.text;
      previous.text = previous.text + line.text;
      lines.splice(index, 1);
      closeMenusForTyping();
      render({ focusId: previous.id, caret: previousText.length });
      setStatus("Lines joined.");
      return true;
    }

    function focusExit() {
      var exit = $(".demo-exit");
      if (exit) {
        exit.focus();
      } else if (demoReset) {
        demoReset.focus();
      }
    }

    function moveLineFocus(direction) {
      var line = focusedLine();
      var ta = currentTextarea();
      if (!line || !ta) return false;
      var index = indexById(line.id);
      var nextIndex = index + direction;
      if (nextIndex < 0 || nextIndex >= lines.length) return false;
      if (direction < 0 && ta.selectionStart !== 0) return false;
      if (direction > 0 && ta.selectionStart !== line.text.length) return false;
      var next = lines[nextIndex];
      focusLine(next.id, direction > 0 ? 0 : next.text.length);
      setStatus(describe(next));
      return true;
    }

    editor.addEventListener("compositionstart", function () {
      composing = true;
    });
    editor.addEventListener("compositionend", function () {
      composing = false;
      var ta = document.activeElement;
      if (ta && ta.tagName === "TEXTAREA") {
        handleInput({ target: ta });
      }
    });

    editor.addEventListener("input", handleInput);

    editor.addEventListener("focusin", function (event) {
      var ta = event.target;
      if (!ta || ta.tagName !== "TEXTAREA") return;
      var row = ta.closest(".el");
      if (!row) return;
      focusId = row.getAttribute("data-id");
      var line = focusedLine();
      if (!line) return;
      if (line.type === "new" && !line.text) openChooser(chooser.open ? chooser.index : 0);
      else if (chooser.open) closeChooser();
      updateGhost();
      if (!ghost) setStatus(describe(line));
    });

    editor.addEventListener("focusout", function (event) {
      var next = event.relatedTarget;
      if (next && (next.closest(".element-chooser") || next.closest(".time-menu"))) return;
      if (next && next.tagName === "TEXTAREA") return;
      /* A structural render removes the old textarea before the new one has
         taken focus, so focusout arrives with no relatedTarget. Wait a frame
         and check where focus actually landed before tearing the page down. */
      window.requestAnimationFrame(function () {
        var active = document.activeElement;
        if (active && active.tagName === "TEXTAREA" && editor.contains(active)) return;
        closeChooser();
        closeTimeMenu();
        ghost = null;
        focusId = null;
      });
    });

    editor.addEventListener("keydown", function (event) {
      var ta = event.target;
      if (!ta || ta.tagName !== "TEXTAREA") return;
      if (composing) return;
      var line = focusedLine();
      if (!line) return;

      if (event.key === "Escape") {
        event.preventDefault();
        if (timeMenu.open) {
          closeTimeMenu();
          setStatus("Time left as typed.");
          return;
        }
        if (chooser.open) {
          closeChooser();
          setStatus("Choose later with Tab, or keep typing.");
          return;
        }
        ta.blur();
        focusExit();
        setStatus("Left the page. Tab to keep going, or click a line to return.");
        return;
      }

      if (timeMenu.open) {
        if (event.key === "ArrowDown" || event.key === "ArrowRight") {
          event.preventDefault();
          moveTime(1);
          return;
        }
        if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
          event.preventDefault();
          moveTime(-1);
          return;
        }
        if (event.key === "Enter") {
          event.preventDefault();
          chooseTime(timeMenu.index, true);
          return;
        }
        if (event.key === "Tab") {
          closeTimeMenu();
          /* Fall through to type cycling. */
        } else if (event.key.length === 1) {
          closeTimeMenu();
        }
      }

      if (chooser.open) {
        if (event.key === "ArrowDown") {
          event.preventDefault();
          moveChooser(1);
          return;
        }
        if (event.key === "ArrowUp") {
          event.preventDefault();
          moveChooser(-1);
          return;
        }
        if (event.key === "Enter") {
          event.preventDefault();
          applyChoice(chooser.index);
          return;
        }
        if (event.key === "Escape") {
          event.preventDefault();
          closeChooser();
          return;
        }
        if (event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
          closeChooser();
        }
      }

      if (event.key === "Tab") {
        event.preventDefault();
        closeChooser();
        closeTimeMenu();
        cycleType(event.shiftKey ? -1 : 1);
        return;
      }

      if (event.key === "Enter" && !event.shiftKey) {
        handleEnter(event);
        return;
      }

      if (event.key === "Backspace" && ta.selectionStart === 0 && ta.selectionEnd === 0) {
        if (mergeBackspace()) event.preventDefault();
        return;
      }

      if (event.key === "ArrowRight" && ghost && ta.selectionStart === line.text.length) {
        event.preventDefault();
        acceptGhost();
        return;
      }

      if ((event.key === "ArrowDown" || event.key === "ArrowUp") && !event.shiftKey) {
        var direction = event.key === "ArrowDown" ? 1 : -1;
        if (moveLineFocus(direction)) event.preventDefault();
        return;
      }

      if (event.key === "(" && line.type === "dialogue" && !line.text) {
        event.preventDefault();
        line.text = "()";
        line.type = "paren";
        var row = rowFor(line.id);
        setRowType(row, line);
        var current = currentTextarea();
        if (current) {
          current.value = "()";
          current.setSelectionRange(1, 1);
          autosize(current);
        }
        decorate();
        setStatus("Parenthetical. Enter goes back to dialogue.");
      }
    });

    paper.addEventListener("click", function (event) {
      if (event.target.closest("textarea, button, a, .element-chooser, .time-menu")) return;
      var last = lines[lines.length - 1];
      if (!last) return;
      focusLine(last.id, last.text.length);
      if (last.type === "new" && !last.text) openChooser(chooser.open ? chooser.index : 0);
    });

    if (demoReset) {
      demoReset.addEventListener("click", function () {
        lines = INITIAL.map(function (item) {
          return makeLine(item[0], item[1]);
        });
        focusId = null;
        closeChooser();
        closeTimeMenu();
        ghost = null;
        render({ focusId: lines[lines.length - 1].id, caret: 0, openChooser: true });
        setStatus("Back to the first page. Type to continue.");
      });
    }

    window.addEventListener("resize", function () {
      autosizeAll();
      if (chooser.open) {
        var menu = $(".element-chooser", chooserLayer);
        if (menu) positionPopover(menu);
      }
      if (timeMenu.open) {
        var menuTime = $(".time-menu", chooserLayer);
        if (menuTime) positionPopover(menuTime);
      }
    });

    document.addEventListener("pointerdown", function (event) {
      if (!chooser.open && !timeMenu.open) return;
      if (event.target.closest(".element-chooser, .time-menu, textarea")) return;
      closeChooser();
      closeTimeMenu();
    });

    render();
  }

  /* ---------------------------------------------------------
     Formatting demo
     --------------------------------------------------------- */

  var formatLine = $("#format-line");
  var formatText = $("#format-text");
  var formatButtons = $$("[data-format]");
  var formatStatus = $("#format-status");
  var FORMAT_EXAMPLES = {
    action: "The cat does not believe her.",
    character: "MAYA",
    scene: "INT. KITCHEN TABLE - 2 AM",
    transition: "CUT TO:"
  };

  if (formatLine && formatText && formatButtons.length) {
    formatLine.setAttribute("data-format", "character");
    formatButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        var value = button.getAttribute("data-format");
        formatLine.setAttribute("data-format", value);
        formatText.textContent = FORMAT_EXAMPLES[value] || "";
        formatButtons.forEach(function (other) {
          other.setAttribute("aria-pressed", other === button ? "true" : "false");
        });
        if (formatStatus) {
          formatStatus.textContent = TYPE_LABEL(value) + ". " + FORMAT_EXAMPLES[value];
        }
      });
    });
  }

  function TYPE_LABEL(value) {
    var labels = { action: "Action", character: "Character", scene: "Scene", transition: "Transition" };
    return labels[value] || value;
  }

  /* ---------------------------------------------------------
     Side panel tabs
     --------------------------------------------------------- */

  var tabList = $(".sp-tabs");
  if (tabList) {
    var tabs = $$('[role="tab"]', tabList);
    function selectTab(tab, focus) {
      tabs.forEach(function (item) {
        var selected = item === tab;
        item.setAttribute("aria-selected", selected ? "true" : "false");
        item.setAttribute("tabindex", selected ? "0" : "-1");
        var panel = document.getElementById(item.getAttribute("aria-controls"));
        if (panel) panel.hidden = !selected;
      });
      if (focus) tab.focus();
    }
    tabs.forEach(function (tab, index) {
      tab.addEventListener("click", function () {
        selectTab(tab, false);
      });
      tab.addEventListener("keydown", function (event) {
        if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
          event.preventDefault();
          var step = event.key === "ArrowRight" ? 1 : -1;
          var next = tabs[(index + step + tabs.length) % tabs.length];
          selectTab(next, true);
        }
      });
    });
    selectTab(tabs[0], false);
  }

  /* ---------------------------------------------------------
     Full UI preview
     --------------------------------------------------------- */

  var uiButtons = $$("[data-ui-mode]");
  var fullUi = $(".full-ui");
  if (uiButtons.length && fullUi) {
    var uiLabel = $("[data-ui-label]");
    uiButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        var mode = button.getAttribute("data-ui-mode");
        fullUi.setAttribute("data-ui-mode", mode);
        uiButtons.forEach(function (other) {
          other.setAttribute("aria-pressed", other === button ? "true" : "false");
        });
        $$(".ui-shot", fullUi).forEach(function (image) {
          var active = image.getAttribute("data-shot") === mode;
          image.classList.toggle("is-active", active);
          if (active) {
            image.loading = "eager";
            if (image.decode) image.decode().catch(function () {});
          }
        });
        if (uiLabel) uiLabel.textContent = TYPE_LABEL_MODE(mode);
      });
    });
  }

  function TYPE_LABEL_MODE(mode) {
    return LAMP_TITLES[mode] || mode;
  }

  /* ---------------------------------------------------------
     Music player
     --------------------------------------------------------- */

  var music = $("#music-player");
  if (music) {
    var tracks = [
      {
        title: "Night Drive",
        length: 245,
        elapsed: 49,
        art: ["#4f4057", "#8c5b62", "#df9a68"],
        bars: ["#4E9396", "#6C9A70", "#C99A3E", "#D0664A", "#A8607C"],
        sun: "#ffdca6",
        road: "#2c2523"
      },
      {
        title: "Paper Lanterns",
        length: 198,
        elapsed: 0,
        art: ["#325652", "#7e8f60", "#e7c07a"],
        bars: ["#6C9A70", "#8A8B4A", "#C99A3E", "#B8744C", "#4E9396"],
        sun: "#fff0c6",
        road: "#1f2a25"
      },
      {
        title: "The Long Way Home",
        length: 312,
        elapsed: 0,
        art: ["#3f3a4d", "#9b5b4e", "#d9a06d"],
        bars: ["#A8607C", "#D0664A", "#C99A3E", "#B8744C", "#4E9396"],
        sun: "#ffe1b4",
        road: "#2a2220"
      }
    ];
    var musicIndex = 0;
    var playing = true;
    var musicTimer = null;
    var toggle = $("#music-toggle");
    var title = $("#track-title");
    var elapsedNode = $("#music-elapsed");
    var totalNode = $("#music-total");
    var musicStatus = $("#music-status");
    var wave = $("#waveform");
    var album = $("#album-art");

    function formatTime(seconds) {
      var m = Math.floor(seconds / 60);
      var s = Math.floor(seconds % 60);
      return m + ":" + (s < 10 ? "0" : "") + s;
    }

    var seeded = 13;
    function random() {
      seeded = (seeded * 16807) % 2147483647;
      return seeded / 2147483647;
    }

    function buildWave(track) {
      if (!wave) return;
      wave.replaceChildren();
      for (var i = 0; i < 44; i += 1) {
        var bar = document.createElement("i");
        var amp = 0.24 + random() * 0.76;
        if (i % 11 === 0) amp = 0.95;
        if (i % 7 === 0) amp = Math.max(amp, 0.72);
        bar.style.setProperty("--amp", amp.toFixed(2));
        bar.style.setProperty("--i", i);
        bar.style.setProperty("--bar", track.bars[i % track.bars.length]);
        wave.appendChild(bar);
      }
    }

    function paintTrack() {
      var track = tracks[musicIndex];
      if (title) title.textContent = track.title;
      if (totalNode) totalNode.textContent = formatTime(track.length);
      if (elapsedNode) elapsedNode.textContent = formatTime(track.elapsed);
      if (album) {
        album.style.background = "linear-gradient(150deg, " + track.art[0] + " 0%, " + track.art[1] + " 48%, " + track.art[2] + " 100%)";
        var sun = $(".album-sun", album);
        var road = $(".album-road", album);
        if (sun) sun.style.background = track.sun;
        if (road) road.style.background = track.road;
      }
      buildWave(track);
      updateMusicButton();
    }

    function updateMusicButton() {
      if (!toggle) return;
      toggle.setAttribute("aria-pressed", playing ? "true" : "false");
      toggle.setAttribute("aria-label", (playing ? "Pause " : "Play ") + tracks[musicIndex].title);
      music.classList.toggle("is-playing", playing);
    }

    function tick() {
      if (!playing) return;
      var track = tracks[musicIndex];
      track.elapsed += 1;
      if (track.elapsed >= track.length) {
        track.elapsed = 0;
        musicIndex = (musicIndex + 1) % tracks.length;
        paintTrack();
        if (musicStatus) musicStatus.textContent = "Now playing " + tracks[musicIndex].title;
      } else if (elapsedNode) {
        elapsedNode.textContent = formatTime(track.elapsed);
      }
    }

    function setPlaying(value) {
      playing = value;
      updateMusicButton();
      if (musicStatus) musicStatus.textContent = playing ? "Playing " + tracks[musicIndex].title : "Paused";
    }

    toggle.addEventListener("click", function () {
      setPlaying(!playing);
    });

    var prev = $("#music-prev");
    var next = $("#music-next");
    if (prev) {
      prev.addEventListener("click", function () {
        musicIndex = (musicIndex - 1 + tracks.length) % tracks.length;
        tracks[musicIndex].elapsed = 0;
        paintTrack();
        if (musicStatus) musicStatus.textContent = "Now playing " + tracks[musicIndex].title;
      });
    }
    if (next) {
      next.addEventListener("click", function () {
        musicIndex = (musicIndex + 1) % tracks.length;
        tracks[musicIndex].elapsed = 0;
        paintTrack();
        if (musicStatus) musicStatus.textContent = "Now playing " + tracks[musicIndex].title;
      });
    }

    paintTrack();
    musicTimer = window.setInterval(tick, 1000);
  }

  /* ---------------------------------------------------------
     FAQ (native details; this only tidies older browsers)
     --------------------------------------------------------- */

  var faqItems = $$(".faq-item");
  faqItems.forEach(function (item) {
    item.addEventListener("toggle", function () {
      if (!item.open) return;
      if (item.getAttribute("name") !== "questions") return;
      faqItems.forEach(function (other) {
        if (other !== item && other.open) other.open = false;
      });
    });
  });

  /* ---------------------------------------------------------
     Footer year (kept exact to the copy)
     --------------------------------------------------------- */

  /* The copy is fixed at 2026 on purpose. */
})();
