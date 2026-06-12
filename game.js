// Inbox Runner — a 2D side-scroller MVP.
//
// Run left to right to the flag at the end of each level while dodging incoming
// emails. Briefly freeze every email to slip past a wall of them.
//
// Controls:
//   Move    — Left/Right arrows or A/D   (or the ◀ ▶ pad on touch)
//   Jump    — Up / W / Space             (or the JUMP button on touch)
//   Freeze  — F or Shift                 (or the FREEZE button on touch)
//   Pause   — P / pause button           Mute — M / mute button
//
// Built on Phaser 3. All art and sound are generated at runtime, so there are
// no asset files. The canvas scales to fit any screen and supports touch.

const WIDTH = 800;
const HEIGHT = 600;
const GROUND_HEIGHT = 64;

// Per-level configuration. Add more objects here to add levels.
const LEVELS = [
  { length: 3200, emailRate: 1400, emailSpeed: 220, freezeCharges: 3 },
  { length: 4200, emailRate: 1100, emailSpeed: 280, freezeCharges: 3 },
  { length: 5200, emailRate: 850, emailSpeed: 340, freezeCharges: 4 },
];

const FREEZE_DURATION = 1800; // ms each freeze lasts
const START_LIVES = 3;
const LEVEL_BONUS = 250; // score for clearing a level

// --- Run state (persists across scenes / restarts) --------------------------
let levelIndex = 0;
let lives = START_LIVES;
let score = 0;
let highScore = Number(localStorage.getItem("inboxRunnerHigh") || 0);

function resetRun() {
  levelIndex = 0;
  lives = START_LIVES;
  score = 0;
}

function commitHighScore(total) {
  if (total > highScore) {
    highScore = total;
    try {
      localStorage.setItem("inboxRunnerHigh", String(highScore));
    } catch (e) {
      /* storage may be unavailable; ignore */
    }
  }
}

// --- Sound (Web Audio synth, no asset files) --------------------------------
const Sfx = {
  ctx: null,
  muted: false,
  init() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) this.ctx = new AC();
    }
    if (this.ctx && this.ctx.state === "suspended") this.ctx.resume();
  },
  note(freq, start, dur, type, vol) {
    if (!this.ctx || this.muted) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, start);
    gain.gain.setValueAtTime(vol, start);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    osc.connect(gain).connect(this.ctx.destination);
    osc.start(start);
    osc.stop(start + dur);
  },
  play(freq, dur = 0.12, type = "square", vol = 0.12) {
    if (!this.ctx) return;
    this.note(freq, this.ctx.currentTime, dur, type, vol);
  },
  arp(freqs, step = 0.09, type = "square", vol = 0.12) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    freqs.forEach((f, i) => this.note(f, t + i * step, step * 1.3, type, vol));
  },
  jump() {
    this.play(520, 0.1, "square", 0.1);
  },
  hit() {
    this.play(150, 0.2, "sawtooth", 0.14);
  },
  freeze() {
    this.arp([880, 1175], 0.08, "sine", 0.12);
  },
  levelClear() {
    this.arp([523, 659, 784, 1047], 0.1);
  },
  gameOver() {
    this.arp([392, 311, 247, 196], 0.13, "triangle");
  },
};

// ===========================================================================
//  BootScene — generates every texture, then hands off to the title screen.
// ===========================================================================
class BootScene extends Phaser.Scene {
  constructor() {
    super("boot");
  }

  create() {
    const g = () => this.make.graphics({ x: 0, y: 0, add: false });

    // Player: a friendly rounded square with eyes.
    let p = g();
    p.fillStyle(0x5cc8ff, 1);
    p.fillRoundedRect(0, 0, 36, 44, 8);
    p.fillStyle(0xffffff, 1);
    p.fillCircle(12, 16, 5);
    p.fillCircle(26, 16, 5);
    p.fillStyle(0x1d1f2b, 1);
    p.fillCircle(13, 17, 2.5);
    p.fillCircle(27, 17, 2.5);
    p.generateTexture("player", 36, 44);
    p.destroy();

    // Email: an envelope.
    let e = g();
    e.fillStyle(0xfff4d6, 1);
    e.fillRoundedRect(0, 0, 40, 28, 4);
    e.lineStyle(2, 0xd9a441, 1);
    e.strokeRoundedRect(1, 1, 38, 26, 4);
    e.beginPath();
    e.moveTo(2, 3);
    e.lineTo(20, 17);
    e.lineTo(38, 3);
    e.strokePath();
    e.generateTexture("email", 40, 28);
    e.destroy();

    // Ground tile.
    let gr = g();
    gr.fillStyle(0x2c2f44, 1);
    gr.fillRect(0, 0, 64, GROUND_HEIGHT);
    gr.fillStyle(0x3a3e5c, 1);
    gr.fillRect(0, 0, 64, 6);
    gr.generateTexture("ground", 64, GROUND_HEIGHT);
    gr.destroy();

    // Goal flag.
    let f = g();
    f.fillStyle(0xbfc4dc, 1);
    f.fillRect(0, 0, 6, 120);
    f.fillStyle(0x6bd968, 1);
    f.fillTriangle(6, 6, 6, 40, 48, 23);
    f.generateTexture("goal", 48, 120);
    f.destroy();

    // Sky: vertical gradient.
    let sky = g();
    const top = Phaser.Display.Color.ValueToColor(0x2a2d4a);
    const bot = Phaser.Display.Color.ValueToColor(0x15161f);
    for (let y = 0; y < HEIGHT; y++) {
      const c = Phaser.Display.Color.Interpolate.ColorWithColor(top, bot, HEIGHT, y);
      sky.fillStyle(Phaser.Display.Color.GetColor(c.r, c.g, c.b), 1);
      sky.fillRect(0, y, WIDTH, 1);
    }
    sky.generateTexture("sky", WIDTH, HEIGHT);
    sky.destroy();

    // Stars: a tiling transparent strip of dots (far parallax layer).
    let st = g();
    for (let i = 0; i < 40; i++) {
      const a = Phaser.Math.FloatBetween(0.3, 0.9);
      st.fillStyle(0xffffff, a);
      st.fillCircle(Phaser.Math.Between(0, 256), Phaser.Math.Between(0, HEIGHT), Phaser.Math.Between(1, 2));
    }
    st.generateTexture("stars", 256, HEIGHT);
    st.destroy();

    // Buildings: a tiling silhouette strip (near parallax layer).
    let b = g();
    b.fillStyle(0x232539, 1);
    let x = 0;
    while (x < 256) {
      const w = Phaser.Math.Between(28, 56);
      const h = Phaser.Math.Between(70, 190);
      b.fillRect(x, 200 - h, w, h);
      // a few lit windows
      b.fillStyle(0x3a3e5c, 1);
      for (let wy = 200 - h + 8; wy < 196; wy += 16) {
        if (Math.random() > 0.5) b.fillRect(x + 6, wy, 6, 6);
      }
      b.fillStyle(0x232539, 1);
      x += w + Phaser.Math.Between(6, 16);
    }
    b.generateTexture("buildings", 256, 200);
    b.destroy();

    this.scene.start("title");
  }
}

// ===========================================================================
//  TitleScene — start screen with the high score and a start prompt.
// ===========================================================================
class TitleScene extends Phaser.Scene {
  constructor() {
    super("title");
  }

  create() {
    this.add.image(0, 0, "sky").setOrigin(0);
    this.add.tileSprite(0, 0, WIDTH, HEIGHT, "stars").setOrigin(0).setAlpha(0.6);
    this.add.tileSprite(0, HEIGHT - GROUND_HEIGHT - 200, WIDTH, 200, "buildings").setOrigin(0);
    this.add.tileSprite(0, HEIGHT - GROUND_HEIGHT, WIDTH, GROUND_HEIGHT, "ground").setOrigin(0);

    this.add.image(WIDTH / 2 - 120, HEIGHT / 2 - 40, "player").setScale(2);
    this.add.image(WIDTH / 2 + 120, HEIGHT / 2 - 60, "email").setScale(1.6).setAngle(-12);

    this.add
      .text(WIDTH / 2, 150, "INBOX RUNNER", {
        fontFamily: "system-ui, sans-serif",
        fontSize: "56px",
        fontStyle: "bold",
        color: "#ffffff",
      })
      .setOrigin(0.5);

    this.add
      .text(WIDTH / 2, 205, "Dodge the emails. Reach the flag.", {
        fontFamily: "system-ui, sans-serif",
        fontSize: "20px",
        color: "#9aa0b5",
      })
      .setOrigin(0.5);

    const isTouch = this.sys.game.device.input.touch;
    const controls = isTouch
      ? "Use the on-screen pad to move, JUMP and FREEZE"
      : "Arrows/A,D to move  •  Up/Space to jump  •  F to freeze";
    this.add
      .text(WIDTH / 2, HEIGHT - 150, controls, {
        fontFamily: "system-ui, sans-serif",
        fontSize: "16px",
        color: "#9aa0b5",
        align: "center",
      })
      .setOrigin(0.5);

    if (highScore > 0) {
      this.add
        .text(WIDTH / 2, HEIGHT - 115, "Best: " + highScore, {
          fontFamily: "system-ui, sans-serif",
          fontSize: "18px",
          color: "#ffd166",
        })
        .setOrigin(0.5);
    }

    const prompt = this.add
      .text(WIDTH / 2, HEIGHT - 75, isTouch ? "Tap to start" : "Press any key or click to start", {
        fontFamily: "system-ui, sans-serif",
        fontSize: "22px",
        color: "#ffffff",
      })
      .setOrigin(0.5);
    this.tweens.add({ targets: prompt, alpha: 0.3, duration: 700, yoyo: true, repeat: -1 });

    const start = () => {
      Sfx.init();
      resetRun();
      this.scene.start("game");
    };
    this.input.keyboard.once("keydown", start);
    this.input.once("pointerdown", start);
  }
}

// ===========================================================================
//  GameScene — the playable level.
// ===========================================================================
class GameScene extends Phaser.Scene {
  constructor() {
    super("game");
  }

  create() {
    this.levelOver = false;
    this.paused = false;
    this.restartRequested = false;
    this.frozenUntil = 0;
    this.invulnUntil = 0;
    this.maxX = 0;
    this.touch = { left: false, right: false, jump: false, freezeQueued: false };

    const level = LEVELS[levelIndex];
    this.freezeCharges = level.freezeCharges;
    const groundY = HEIGHT - GROUND_HEIGHT;

    // Parallax background.
    this.add.image(0, 0, "sky").setOrigin(0).setScrollFactor(0).setDepth(-30);
    this.stars = this.add.tileSprite(0, 0, WIDTH, HEIGHT, "stars").setOrigin(0).setScrollFactor(0).setDepth(-20).setAlpha(0.6);
    this.buildings = this.add
      .tileSprite(0, groundY - 200, WIDTH, 200, "buildings")
      .setOrigin(0)
      .setScrollFactor(0)
      .setDepth(-10);

    // World wider than the screen; camera follows the player.
    this.physics.world.setBounds(0, 0, level.length, HEIGHT);
    this.cameras.main.setBounds(0, 0, level.length, HEIGHT);

    this.ground = this.add.tileSprite(0, groundY, level.length, GROUND_HEIGHT, "ground").setOrigin(0, 0);
    this.physics.add.existing(this.ground, true);

    this.player = this.physics.add.sprite(80, groundY - 60, "player");
    this.player.setCollideWorldBounds(true);
    this.player.body.setSize(36, 44);
    this.physics.add.collider(this.player, this.ground);
    this.cameras.main.startFollow(this.player, true, 0.1, 0.1);

    this.goal = this.physics.add.staticImage(level.length - 80, groundY - 60, "goal");
    this.goal.body.setSize(48, 120);

    this.emails = this.physics.add.group({ allowGravity: false });
    this.physics.add.overlap(this.player, this.emails, this.onEmailHit, null, this);

    this.emailTimer = this.time.addEvent({
      delay: level.emailRate,
      loop: true,
      callback: this.spawnEmail,
      callbackScope: this,
    });

    // Input.
    this.cursors = this.input.keyboard.createCursorKeys();
    this.keys = this.input.keyboard.addKeys("W,A,D,F,SHIFT,SPACE,R,P,M");
    this.input.addPointer(2);
    this.isTouch = this.sys.game.device.input.touch;
    if (this.isTouch) this.createTouchControls();
    this.input.on("pointerdown", () => {
      if (this.levelOver) this.restartRequested = true;
    });

    this.createUI();
  }

  // --- Spawning -------------------------------------------------------------
  spawnEmail() {
    if (this.levelOver || this.paused) return;
    const level = LEVELS[levelIndex];
    const cam = this.cameras.main;
    const x = cam.scrollX + WIDTH + 40;
    const y = Phaser.Math.Between(120, HEIGHT - GROUND_HEIGHT - 30);
    const email = this.emails.create(x, y, "email");
    email.setVelocityX(-Phaser.Math.Between(level.emailSpeed - 40, level.emailSpeed + 60));
    email.body.setSize(40, 28);
  }

  // --- UI: HUD + pause/mute buttons + touch pad -----------------------------
  createUI() {
    this.hud = this.add
      .text(16, 14, "", {
        fontFamily: "system-ui, sans-serif",
        fontSize: "18px",
        color: "#ffffff",
        lineSpacing: 4,
      })
      .setScrollFactor(0)
      .setDepth(40);

    // Pause + mute buttons (work with mouse or touch).
    this.pauseBtn = this.cornerButton(WIDTH - 96, 26, "⏸", () => this.togglePause());
    this.muteBtn = this.cornerButton(WIDTH - 40, 26, Sfx.muted ? "🔇" : "🔊", () => this.toggleMute());
  }

  cornerButton(x, y, label, onClick) {
    const bg = this.add
      .circle(x, y, 22, 0x000000, 0.35)
      .setScrollFactor(0)
      .setDepth(40)
      .setStrokeStyle(2, 0xffffff, 0.4)
      .setInteractive(new Phaser.Geom.Circle(22, 22, 22), Phaser.Geom.Circle.Contains);
    const txt = this.add
      .text(x, y, label, { fontSize: "20px" })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setDepth(41);
    bg.on("pointerdown", (p, lx, ly, ev) => {
      if (ev) ev.stopPropagation();
      onClick();
    });
    bg.label = txt;
    return bg;
  }

  createTouchControls() {
    const makeButton = (x, y, r, label, color) => {
      const circle = this.add
        .circle(x, y, r, color, 0.28)
        .setScrollFactor(0)
        .setDepth(40)
        .setStrokeStyle(2, 0xffffff, 0.5)
        .setInteractive(new Phaser.Geom.Circle(r, r, r), Phaser.Geom.Circle.Contains);
      this.add
        .text(x, y, label, { fontFamily: "system-ui, sans-serif", fontSize: "16px", color: "#ffffff" })
        .setOrigin(0.5)
        .setScrollFactor(0)
        .setDepth(41);
      return circle;
    };

    const baseY = HEIGHT - 70;
    const leftBtn = makeButton(70, baseY, 42, "◀", 0x5cc8ff);
    const rightBtn = makeButton(168, baseY, 42, "▶", 0x5cc8ff);
    const jumpBtn = makeButton(WIDTH - 70, baseY, 46, "JUMP", 0x6bd968);
    const freezeBtn = makeButton(WIDTH - 168, baseY - 10, 40, "FREEZE", 0x7fd0ff);

    const hold = (btn, key) => {
      btn.on("pointerdown", () => (this.touch[key] = true));
      btn.on("pointerup", () => (this.touch[key] = false));
      btn.on("pointerout", () => (this.touch[key] = false));
    };
    hold(leftBtn, "left");
    hold(rightBtn, "right");
    hold(jumpBtn, "jump");
    freezeBtn.on("pointerdown", () => (this.touch.freezeQueued = true));
  }

  // --- Pause / mute ---------------------------------------------------------
  togglePause() {
    if (this.levelOver) return;
    this.paused = !this.paused;
    if (this.paused) {
      this.physics.pause();
      this.emailTimer.paused = true;
      this.pauseBtn.label.setText("▶");
      this.pauseText = this.add
        .text(WIDTH / 2, HEIGHT / 2, "Paused\n" + (this.isTouch ? "Tap pause to resume" : "Press P to resume"), {
          fontFamily: "system-ui, sans-serif",
          fontSize: "30px",
          color: "#ffffff",
          align: "center",
          backgroundColor: "#00000088",
          padding: { x: 24, y: 18 },
        })
        .setOrigin(0.5)
        .setScrollFactor(0)
        .setDepth(50);
    } else {
      this.physics.resume();
      this.emailTimer.paused = false;
      this.pauseBtn.label.setText("⏸");
      if (this.pauseText) this.pauseText.destroy();
    }
  }

  toggleMute() {
    Sfx.muted = !Sfx.muted;
    this.muteBtn.label.setText(Sfx.muted ? "🔇" : "🔊");
  }

  // --- Update loop ----------------------------------------------------------
  update(time) {
    if (!this.player) return;

    if (Phaser.Input.Keyboard.JustDown(this.keys.P)) this.togglePause();
    if (Phaser.Input.Keyboard.JustDown(this.keys.M)) this.toggleMute();

    // Parallax follows the camera even while paused/over.
    const sx = this.cameras.main.scrollX;
    this.stars.tilePositionX = sx * 0.2;
    this.buildings.tilePositionX = sx * 0.5;

    if (this.paused) return;

    const frozen = time < this.frozenUntil;

    if (this.levelOver) {
      if (Phaser.Input.Keyboard.JustDown(this.keys.R) || this.restartRequested) {
        this.restartRequested = false;
        this.advance();
      }
      this.drawHud(frozen);
      return;
    }

    // Movement.
    const left = this.cursors.left.isDown || this.keys.A.isDown || this.touch.left;
    const right = this.cursors.right.isDown || this.keys.D.isDown || this.touch.right;
    if (left) {
      this.player.setVelocityX(-260);
      this.player.setFlipX(true);
    } else if (right) {
      this.player.setVelocityX(260);
      this.player.setFlipX(false);
    } else {
      this.player.setVelocityX(0);
    }

    const jump = this.cursors.up.isDown || this.keys.W.isDown || this.keys.SPACE.isDown || this.touch.jump;
    if (jump && this.player.body.blocked.down) {
      this.player.setVelocityY(-650);
      Sfx.jump();
    }

    // Freeze.
    const freezePressed =
      Phaser.Input.Keyboard.JustDown(this.keys.F) ||
      Phaser.Input.Keyboard.JustDown(this.keys.SHIFT) ||
      this.touch.freezeQueued;
    this.touch.freezeQueued = false;
    if (freezePressed && this.freezeCharges > 0 && !frozen) {
      this.freezeCharges -= 1;
      this.frozenUntil = time + FREEZE_DURATION;
      Sfx.freeze();
    }

    // Freeze / unfreeze emails and recycle off-screen ones.
    this.emails.children.iterate((email) => {
      if (!email || !email.active) return;
      if (frozen) {
        if (email.getData("savedVx") === undefined) email.setData("savedVx", email.body.velocity.x);
        email.setVelocityX(0);
        email.setTint(0x7fd0ff);
      } else if (email.getData("savedVx") !== undefined) {
        email.setVelocityX(email.getData("savedVx"));
        email.setData("savedVx", undefined);
        email.clearTint();
      }
      if (email.x < this.cameras.main.scrollX - 60) email.destroy();
    });

    this.player.setAlpha(time < this.invulnUntil ? 0.5 : 1);
    this.maxX = Math.max(this.maxX, this.player.x - 80);

    if (this.player.x >= this.goal.x - 30) this.winLevel();

    this.drawHud(frozen);
  }

  // --- Outcomes -------------------------------------------------------------
  onEmailHit(playerObj, email) {
    const now = this.time.now;
    if (now < this.invulnUntil || this.levelOver) return;
    email.destroy();
    lives -= 1;
    this.invulnUntil = now + 1200;
    this.cameras.main.shake(150, 0.01);
    Sfx.hit();
    if (lives <= 0) this.gameOver();
  }

  winLevel() {
    if (this.levelOver) return;
    this.levelOver = true;
    this.emailTimer.remove();
    score += Math.floor(this.maxX / 10) + LEVEL_BONUS;

    if (levelIndex < LEVELS.length - 1) {
      Sfx.levelClear();
      this.showBanner("Level cleared!\nScore: " + score + "\n" + this.hint());
    } else {
      commitHighScore(score);
      Sfx.levelClear();
      this.showBanner("You beat your inbox!\nScore: " + score + "\n" + this.hint());
    }
  }

  gameOver() {
    this.levelOver = true;
    this.emailTimer.remove();
    const total = score + Math.floor(this.maxX / 10);
    score = total;
    commitHighScore(total);
    Sfx.gameOver();
    this.showBanner("Buried in email...\nScore: " + total + "   Best: " + highScore + "\n" + this.hint());
  }

  // Move to the next state once the player asks to continue.
  advance() {
    if (lives <= 0) {
      // Run is over — back to the title for a fresh start.
      this.scene.start("title");
      return;
    }
    if (levelIndex < LEVELS.length - 1) {
      levelIndex += 1;
    } else {
      // Beat the last level — start a fresh run.
      resetRun();
    }
    this.scene.restart();
  }

  hint() {
    return this.isTouch ? "Tap to continue" : "Press R to continue";
  }

  showBanner(text) {
    this.add
      .text(WIDTH / 2, HEIGHT / 2, text, {
        fontFamily: "system-ui, sans-serif",
        fontSize: "30px",
        color: "#ffffff",
        align: "center",
        backgroundColor: "#00000088",
        padding: { x: 24, y: 18 },
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setDepth(50);
  }

  drawHud(frozen) {
    const level = LEVELS[levelIndex];
    const progress = Math.min(100, Math.round((this.player.x / level.length) * 100));
    const freezeLabel = frozen ? "ACTIVE" : "x" + this.freezeCharges;
    const total = score + Math.floor(this.maxX / 10);
    this.hud.setText(
      [
        "Lives: " + "♥".repeat(Math.max(0, lives)),
        "Freeze: " + freezeLabel,
        "Level " + (levelIndex + 1) + " — " + progress + "%",
        "Score: " + total + "   Best: " + highScore,
      ].join("\n")
    );
  }
}

// ===========================================================================
const config = {
  type: Phaser.AUTO,
  parent: "game",
  backgroundColor: "#15161f",
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
    width: WIDTH,
    height: HEIGHT,
  },
  physics: {
    default: "arcade",
    arcade: { gravity: { y: 1400 }, debug: false },
  },
  scene: [BootScene, TitleScene, GameScene],
};

new Phaser.Game(config);
