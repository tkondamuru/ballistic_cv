// Modular Game: Wall Breakout
export default class BreakoutGame {
  constructor() {
    this.name = "🧱 Wall Breaker";
    this.id = "breakout";
    this.score = 0;
    this.totalBricks = 0;
    this.destroyedBricks = 0;
    this.gameWon = false;

    this.bricks = [];
    this.particles = [];

    this.BRICK_ROWS = 6;
    this.BRICK_COLS = 10;
    this.ROW_COLORS = ['#ff4757', '#ffa502', '#2ed573', '#1e90ff', '#a78bfa', '#ec4899'];
  }

  init(canvas, margin) {
    this.canvas = canvas;
    this.margin = margin || 24;
    this.score = 0;
    this.destroyedBricks = 0;
    this.gameWon = false;
    this.particles = [];

    const savedRows = localStorage.getItem('thud_breakout_rows');
    if (savedRows !== null) this.BRICK_ROWS = parseInt(savedRows) || 6;

    const savedCols = localStorage.getItem('thud_breakout_cols');
    if (savedCols !== null) this.BRICK_COLS = parseInt(savedCols) || 10;

    this.initBricks();
  }

  renderOptions(container) {
    container.innerHTML = `
      <div class="input-group" title="Brick Rows">
        <label>Rows:</label>
        <input type="range" id="brickRowsSlider" min="3" max="8" value="${this.BRICK_ROWS}" style="width: 45px;">
        <span id="brickRowsVal" class="val-readout">${this.BRICK_ROWS}</span>
      </div>
      <div class="input-group" title="Brick Columns">
        <label>Cols:</label>
        <input type="range" id="brickColsSlider" min="5" max="14" value="${this.BRICK_COLS}" style="width: 45px;">
        <span id="brickColsVal" class="val-readout">${this.BRICK_COLS}</span>
      </div>
    `;

    const rowsSlider = container.querySelector('#brickRowsSlider');
    const rowsVal = container.querySelector('#brickRowsVal');
    const colsSlider = container.querySelector('#brickColsSlider');
    const colsVal = container.querySelector('#brickColsVal');

    rowsSlider.addEventListener('input', (e) => {
      this.BRICK_ROWS = parseInt(e.target.value);
      rowsVal.innerText = this.BRICK_ROWS;
      localStorage.setItem('thud_breakout_rows', this.BRICK_ROWS);
      this.initBricks();
    });

    colsSlider.addEventListener('input', (e) => {
      this.BRICK_COLS = parseInt(e.target.value);
      colsVal.innerText = this.BRICK_COLS;
      localStorage.setItem('thud_breakout_cols', this.BRICK_COLS);
      this.initBricks();
    });
  }

  initBricks() {
    const margin = this.margin || 24;
    const wallWidth = this.canvas.width - (2 * margin);
    const wallHeight = (this.canvas.height - (2 * margin)) * 0.55;

    const gap = 8;
    const brickWidth = (wallWidth - (this.BRICK_COLS + 1) * gap) / this.BRICK_COLS;
    const brickHeight = (wallHeight - (this.BRICK_ROWS + 1) * gap) / this.BRICK_ROWS;

    this.bricks = [];
    this.totalBricks = 0;
    this.destroyedBricks = 0;

    for (let r = 0; r < this.BRICK_ROWS; r++) {
      for (let c = 0; c < this.BRICK_COLS; c++) {
        const isArmored = (r === 0) && (c % 2 === 0);
        this.bricks.push({
          x: margin + gap + c * (brickWidth + gap),
          y: margin + gap + r * (brickHeight + gap),
          w: brickWidth,
          h: brickHeight,
          color: this.ROW_COLORS[r % this.ROW_COLORS.length],
          hp: isArmored ? 2 : 1,
          maxHp: isArmored ? 2 : 1,
          isArmored: isArmored
        });
        this.totalBricks++;
      }
    }
  }

  update(dt, margin) {
    this.margin = margin || 24;
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx; p.y += p.vy;
      p.alpha -= p.decay;
      if (p.alpha <= 0) { this.particles.splice(i, 1); }
    }
  }

  createDebris(x, y, w, h, color) {
    for (let i = 0; i < 16; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 2 + Math.random() * 6;
      this.particles.push({
        x: x + Math.random() * w,
        y: y + Math.random() * h,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        size: 4 + Math.random() * 6,
        color: color,
        alpha: 1.0,
        decay: 0.02 + Math.random() * 0.03
      });
    }
  }

  onImpact(u, v, screenX, screenY) {
    if (this.gameWon) return { hit: false };

    let hitAny = false;
    const HIT_RADIUS = 36;

    for (let i = this.bricks.length - 1; i >= 0; i--) {
      const b = this.bricks[i];
      if (b.hp <= 0) continue;

      const closestX = Math.max(b.x, Math.min(screenX, b.x + b.w));
      const closestY = Math.max(b.y, Math.min(screenY, b.y + b.h));
      const dist = Math.hypot(screenX - closestX, screenY - closestY);

      if (dist <= HIT_RADIUS) {
        hitAny = true;
        b.hp--;
        this.score += 150;

        if (b.hp <= 0) {
          this.destroyedBricks++;
          this.createDebris(b.x, b.y, b.w, b.h, b.color);
        }

        if (this.destroyedBricks >= this.totalBricks) {
          this.gameWon = true;
          return {
            hit: true,
            won: true,
            message: `🏆 ALL BRICKS SMASHED! Score: ${this.score}`
          };
        }

        return {
          hit: true,
          won: false,
          message: 'SMASH!'
        };
      }
    }

    return { hit: false, message: 'MISS' };
  }

  draw(ctx) {
    for (const b of this.bricks) {
      if (b.hp <= 0) continue;

      ctx.save();
      ctx.fillStyle = b.hp === 2 ? '#94a3b8' : b.color;
      ctx.shadowColor = b.color;
      ctx.shadowBlur = 8;

      ctx.beginPath();
      ctx.roundRect(b.x, b.y, b.w, b.h, 6);
      ctx.fill();

      ctx.fillStyle = 'rgba(255, 255, 255, 0.25)';
      ctx.beginPath();
      ctx.roundRect(b.x + 2, b.y + 2, b.w - 4, b.h * 0.35, [4, 4, 0, 0]);
      ctx.fill();

      if (b.isArmored) {
        ctx.fillStyle = '#0f172a';
        ctx.font = 'bold 11px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(b.hp === 2 ? '🛡️' : '💥', b.x + b.w / 2, b.y + b.h / 2);
      }

      ctx.restore();
    }

    for (const p of this.particles) {
      ctx.save();
      ctx.globalAlpha = p.alpha;
      ctx.fillStyle = p.color;
      ctx.fillRect(p.x, p.y, p.size, p.size);
      ctx.restore();
    }
  }

  getStatsText() {
    const remaining = this.totalBricks - this.destroyedBricks;
    return `🧱 BRICKS: ${remaining}/${this.totalBricks} | SCORE: ${this.score}`;
  }
}
