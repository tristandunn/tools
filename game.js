// Inbox Runner — a 2D side-scroller.
//
// Goal: reach the flag at the end of each level while dodging incoming emails.
// Controls:
//   Move      — Left/Right arrows or A/D  (or the on-screen pad on touch)
//   Jump      — Up / W / Space            (or the JUMP button on touch)
//   Freeze    — F or Shift                (or the FREEZE button on touch)
//
// Built on Phaser 3. All art is generated at runtime, so there are no asset
// files to load. The canvas scales to fit any screen and supports touch.

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

const config = {
  type: Phaser.AUTO,
  parent: "game",
  backgroundColor: "#1d1f2b",
  // Scale to fit the viewport while keeping the 800x600 aspect ratio.
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
  scene: { preload, create, update },
};

const game = new Phaser.Game(config);

// --- Mutable game state -----------------------------------------------------
let player;
let cursors;
let keys;
let ground;
let goal;
let emails;
let emailTimer;

let levelIndex = 0;
let lives = START_LIVES;
let freezeCharges = 0;
let frozenUntil = 0; // timestamp; emails are frozen while now < frozenUntil
let invulnUntil = 0; // brief mercy window after a hit
let levelOver = false;
let restartRequested = false;

let hud;
let isTouch = false;

// Touch input is funneled into this object and merged with the keyboard.
const touch = { left: false, right: false, jump: false, freezeQueued: false };

// --- Texture generation -----------------------------------------------------
function preload() {
  // Player: a friendly rounded square with eyes.
  const p = this.make.graphics({ x: 0, y: 0, add: false });
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
  const e = this.make.graphics({ x: 0, y: 0, add: false });
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
  const g = this.make.graphics({ x: 0, y: 0, add: false });
  g.fillStyle(0x2c2f44, 1);
  g.fillRect(0, 0, 64, GROUND_HEIGHT);
  g.fillStyle(0x3a3e5c, 1);
  g.fillRect(0, 0, 64, 6);
  g.generateTexture("ground", 64, GROUND_HEIGHT);
  g.destroy();

  // Goal flag.
  const f = this.make.graphics({ x: 0, y: 0, add: false });
  f.fillStyle(0xbfc4dc, 1);
  f.fillRect(0, 0, 6, 120);
  f.fillStyle(0x6bd968, 1);
  f.fillTriangle(6, 6, 6, 40, 48, 23);
  f.generateTexture("goal", 48, 120);
  f.destroy();
}

// --- Scene setup ------------------------------------------------------------
function create() {
  startLevel.call(this);

  cursors = this.input.keyboard.createCursorKeys();
  keys = this.input.keyboard.addKeys("W,A,D,F,SHIFT,SPACE,R");

  // Allow several simultaneous touches (e.g. move + jump at once).
  this.input.addPointer(2);
  isTouch = this.sys.game.device.input.touch;
  if (isTouch) createTouchControls.call(this);

  // Tap anywhere to restart once a level is over (handy on touch).
  this.input.on("pointerdown", () => {
    if (levelOver) restartRequested = true;
  });

  // HUD lives in screen space, so it ignores the camera scroll.
  hud = this.add
    .text(16, 14, "", {
      fontFamily: "system-ui, sans-serif",
      fontSize: "18px",
      color: "#ffffff",
      lineSpacing: 4,
    })
    .setScrollFactor(0)
    .setDepth(10);
}

function startLevel() {
  const level = LEVELS[levelIndex];
  levelOver = false;
  restartRequested = false;
  freezeCharges = level.freezeCharges;
  frozenUntil = 0;
  invulnUntil = 0;

  const groundY = HEIGHT - GROUND_HEIGHT;

  // World is wider than the screen; the camera follows the player.
  this.physics.world.setBounds(0, 0, level.length, HEIGHT);
  this.cameras.main.setBounds(0, 0, level.length, HEIGHT);

  // Ground as a tiled, static body spanning the whole level.
  ground = this.add.tileSprite(0, groundY, level.length, GROUND_HEIGHT, "ground").setOrigin(0, 0);
  this.physics.add.existing(ground, true);

  // Player.
  player = this.physics.add.sprite(80, groundY - 60, "player");
  player.setCollideWorldBounds(true);
  player.body.setSize(36, 44);
  this.physics.add.collider(player, ground);
  this.cameras.main.startFollow(player, true, 0.1, 0.1);

  // Goal flag at the end.
  goal = this.physics.add.staticImage(level.length - 80, groundY - 60, "goal");
  goal.body.setSize(48, 120);

  // Emails group + spawner.
  emails = this.physics.add.group({ allowGravity: false });
  this.physics.add.overlap(player, emails, onEmailHit, null, this);

  if (emailTimer) emailTimer.remove();
  emailTimer = this.time.addEvent({
    delay: level.emailRate,
    loop: true,
    callback: spawnEmail,
    callbackScope: this,
  });
}

function spawnEmail() {
  if (levelOver) return;
  const level = LEVELS[levelIndex];
  const cam = this.cameras.main;

  // Spawn just off the right edge of the view, at a random-ish height.
  const x = cam.scrollX + WIDTH + 40;
  const y = Phaser.Math.Between(120, HEIGHT - GROUND_HEIGHT - 30);

  const email = emails.create(x, y, "email");
  email.setVelocityX(-Phaser.Math.Between(level.emailSpeed - 40, level.emailSpeed + 60));
  email.body.setSize(40, 28);
}

// --- Touch controls ---------------------------------------------------------
function createTouchControls() {
  const makeButton = (x, y, r, label, color) => {
    const circle = this.add
      .circle(x, y, r, color, 0.28)
      .setScrollFactor(0)
      .setDepth(30)
      .setStrokeStyle(2, 0xffffff, 0.5)
      .setInteractive(new Phaser.Geom.Circle(r, r, r), Phaser.Geom.Circle.Contains);
    this.add
      .text(x, y, label, {
        fontFamily: "system-ui, sans-serif",
        fontSize: "16px",
        color: "#ffffff",
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setDepth(31);
    return circle;
  };

  const baseY = HEIGHT - 70;

  // Left / right pad on the bottom-left.
  const leftBtn = makeButton(70, baseY, 42, "◀", 0x5cc8ff);
  const rightBtn = makeButton(168, baseY, 42, "▶", 0x5cc8ff);

  // Jump + freeze on the bottom-right.
  const jumpBtn = makeButton(WIDTH - 70, baseY, 46, "JUMP", 0x6bd968);
  const freezeBtn = makeButton(WIDTH - 168, baseY - 10, 40, "FREEZE", 0x7fd0ff);

  // Held buttons set/clear their flag; releasing or sliding off clears it.
  const hold = (btn, key) => {
    btn.on("pointerdown", () => (touch[key] = true));
    btn.on("pointerup", () => (touch[key] = false));
    btn.on("pointerout", () => (touch[key] = false));
  };
  hold(leftBtn, "left");
  hold(rightBtn, "right");
  hold(jumpBtn, "jump");

  // Freeze is a one-shot: queue it on press, consumed in update().
  freezeBtn.on("pointerdown", () => (touch.freezeQueued = true));
}

// --- Per-frame update -------------------------------------------------------
function update(time) {
  if (!player) return;

  const frozen = time < frozenUntil;

  // Handle restart after game over / win.
  if (levelOver) {
    if (Phaser.Input.Keyboard.JustDown(keys.R) || restartRequested) {
      restartRequested = false;
      this.scene.restart();
      if (lives <= 0) {
        lives = START_LIVES;
        levelIndex = 0;
      }
    }
    drawHud(frozen);
    return;
  }

  // Horizontal movement (keyboard or touch).
  const left = cursors.left.isDown || keys.A.isDown || touch.left;
  const right = cursors.right.isDown || keys.D.isDown || touch.right;
  if (left) {
    player.setVelocityX(-260);
    player.setFlipX(true);
  } else if (right) {
    player.setVelocityX(260);
    player.setFlipX(false);
  } else {
    player.setVelocityX(0);
  }

  // Jump (only when standing on something).
  const jump = cursors.up.isDown || keys.W.isDown || keys.SPACE.isDown || touch.jump;
  if (jump && player.body.blocked.down) {
    player.setVelocityY(-650);
  }

  // Freeze ability (keyboard edge or queued touch press).
  const freezePressed =
    Phaser.Input.Keyboard.JustDown(keys.F) || Phaser.Input.Keyboard.JustDown(keys.SHIFT) || touch.freezeQueued;
  touch.freezeQueued = false;
  if (freezePressed && freezeCharges > 0 && !frozen) {
    freezeCharges -= 1;
    frozenUntil = time + FREEZE_DURATION;
  }

  // Apply / release the freeze on emails, and tint them while frozen.
  emails.children.iterate((email) => {
    if (!email || !email.active) return;
    if (frozen) {
      if (email.getData("savedVx") === undefined) {
        email.setData("savedVx", email.body.velocity.x);
      }
      email.setVelocityX(0);
      email.setTint(0x7fd0ff);
    } else if (email.getData("savedVx") !== undefined) {
      email.setVelocityX(email.getData("savedVx"));
      email.setData("savedVx", undefined);
      email.clearTint();
    }
    // Recycle emails that have passed the player.
    if (email.x < this.cameras.main.scrollX - 60) {
      email.destroy();
    }
  });

  // Flash the player while briefly invulnerable.
  player.setAlpha(time < invulnUntil ? 0.5 : 1);

  // Reached the goal?
  if (player.x >= goal.x - 30) {
    winLevel.call(this);
  }

  drawHud(frozen);
}

// --- Collisions & outcomes --------------------------------------------------
function onEmailHit(playerObj, email) {
  const now = this.time.now;
  if (now < invulnUntil || levelOver) return;

  email.destroy();
  lives -= 1;
  invulnUntil = now + 1200;
  this.cameras.main.shake(150, 0.01);

  if (lives <= 0) {
    gameOver.call(this);
  }
}

function winLevel() {
  if (levelOver) return;
  levelOver = true;
  if (emailTimer) emailTimer.remove();

  if (levelIndex < LEVELS.length - 1) {
    levelIndex += 1;
    showBanner.call(this, "Level cleared!\n" + restartHint());
  } else {
    showBanner.call(this, "You beat your inbox!\n" + restartHint());
    levelIndex = 0; // loop back to the start on replay
  }
}

function gameOver() {
  levelOver = true;
  if (emailTimer) emailTimer.remove();
  showBanner.call(this, "Buried in email...\n" + restartHint());
}

function restartHint() {
  return isTouch ? "Tap to continue" : "Press R to continue";
}

function showBanner(text) {
  this.add
    .text(WIDTH / 2, HEIGHT / 2, text, {
      fontFamily: "system-ui, sans-serif",
      fontSize: "32px",
      color: "#ffffff",
      align: "center",
      backgroundColor: "#00000088",
      padding: { x: 24, y: 18 },
    })
    .setOrigin(0.5)
    .setScrollFactor(0)
    .setDepth(20);
}

// --- HUD --------------------------------------------------------------------
function drawHud(frozen) {
  const level = LEVELS[levelIndex];
  const progress = Math.min(100, Math.round((player.x / level.length) * 100));
  const freezeLabel = frozen ? "ACTIVE" : "x" + freezeCharges;
  hud.setText(
    [
      "Lives: " + "♥".repeat(Math.max(0, lives)),
      "Freeze: " + freezeLabel,
      "Level " + (levelIndex + 1) + " — " + progress + "%",
    ].join("\n")
  );
}
