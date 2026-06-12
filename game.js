// A small playable starter built on Phaser 3.
// Move the paddle with your mouse (or finger) and keep the ball in play.

const WIDTH = 800;
const HEIGHT = 600;

const config = {
  type: Phaser.AUTO,
  width: WIDTH,
  height: HEIGHT,
  parent: "game",
  backgroundColor: "#1d1f2b",
  physics: {
    default: "arcade",
    arcade: { gravity: { y: 0 } },
  },
  scene: { create, update },
};

let paddle;
let ball;
let scoreText;
let score = 0;

new Phaser.Game(config);

function create() {
  // Paddle near the bottom of the screen.
  paddle = this.add.rectangle(WIDTH / 2, HEIGHT - 40, 120, 18, 0x5cc8ff);
  this.physics.add.existing(paddle);
  paddle.body.setImmovable(true);
  paddle.body.allowGravity = false;

  // Ball starts in the middle with a bit of velocity.
  ball = this.add.circle(WIDTH / 2, HEIGHT / 2, 12, 0xffd166);
  this.physics.add.existing(ball);
  ball.body.setBounce(1, 1);
  ball.body.setCollideWorldBounds(true);
  ball.body.setVelocity(200, -200);

  // Bounce the ball off the paddle and add a point each time.
  this.physics.add.collider(ball, paddle, () => {
    score += 1;
    scoreText.setText("Score: " + score);
  });

  scoreText = this.add.text(16, 16, "Score: 0", {
    fontFamily: "system-ui, sans-serif",
    fontSize: "24px",
    color: "#ffffff",
  });

  this.add.text(16, HEIGHT - 28, "Move the paddle with your mouse to keep the ball alive", {
    fontFamily: "system-ui, sans-serif",
    fontSize: "14px",
    color: "#9aa0b5",
  });
}

function update() {
  // Follow the pointer horizontally, clamped to the screen.
  const pointerX = this.input.activePointer.x;
  paddle.x = Phaser.Math.Clamp(pointerX, 60, WIDTH - 60);
  paddle.body.updateFromGameObject();

  // Reset if the ball drops below the paddle.
  if (ball.y > HEIGHT - 10) {
    score = 0;
    scoreText.setText("Score: 0");
    ball.setPosition(WIDTH / 2, HEIGHT / 2);
    ball.body.setVelocity(200, -200);
  }
}
