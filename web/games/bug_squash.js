// Modular Game: Bug Squash (Mosquito Bug Hunter)
export default class BugSquashGame {
  constructor() {
    this.name = "🦟 Bug Squasher";
    this.id = "bug_squash";
    this.totalHits = 0;
    this.targetHits = 5;
    this.gameWon = false;
    this.gameStartTime = null;

    this.bug = {
      x: 300, y: 300,
      targetX: 300, targetY: 300,
      speed: 2.0, size: 28,
      angle: 0, targetAngle: 0,
      legPhase: 0, changeTargetTimer: 0
    };

    this.bloodSplatters = [];
  }

  init(canvas, margin) {
    this.canvas = canvas;
    this.margin = margin;
    this.totalHits = 0;
    this.gameWon = false;
    this.gameStartTime = null;
    this.bloodSplatters = [];

    const savedTarget = localStorage.getItem('thud_target_hits');
    if (savedTarget !== null) {
      this.targetHits = parseInt(savedTarget) || 5;
    }

    const savedSize = localStorage.getItem('thud_bug_size');
    if (savedSize !== null) {
      this.bug.size = parseInt(savedSize) || 28;
    }

    const savedSpeed = localStorage.getItem('thud_bug_speed');
    if (savedSpeed !== null) {
      this.bug.speed = parseFloat(savedSpeed) || 2.0;
    }

    this.pickNewBugTarget();
  }

  renderOptions(container) {
    container.innerHTML = `
      <div class="input-group" title="Bug Crawling Speed (0 = stopped for calibration)">
        <label>Bug Spd:</label>
        <input type="range" id="bugSpeedSlider" min="0" max="5.0" step="0.5" value="${this.bug.speed}" style="width: 45px;">
        <span id="bugSpeedVal" class="val-readout">${this.bug.speed}</span>
      </div>
      <div class="input-group" title="Bug Target Body Size">
        <label>Bug Size:</label>
        <input type="range" id="bugSizeSlider" min="12" max="60" step="2" value="${this.bug.size}" style="width: 45px;">
        <span id="bugSizeVal" class="val-readout">${this.bug.size}px</span>
      </div>
      <div class="input-group" title="Target Squash Goal">
        <label>Target:</label>
        <input type="number" id="targetHitsInput" value="${this.targetHits}" min="1" max="50" style="width: 42px;">
      </div>
    `;

    const bugSpeedSlider = container.querySelector('#bugSpeedSlider');
    const bugSpeedVal = container.querySelector('#bugSpeedVal');
    const bugSizeSlider = container.querySelector('#bugSizeSlider');
    const bugSizeVal = container.querySelector('#bugSizeVal');
    const targetHitsInput = container.querySelector('#targetHitsInput');

    bugSpeedSlider.addEventListener('input', (e) => {
      this.bug.speed = parseFloat(e.target.value);
      bugSpeedVal.innerText = this.bug.speed;
      localStorage.setItem('thud_bug_speed', this.bug.speed);
    });

    bugSizeSlider.addEventListener('input', (e) => {
      this.bug.size = parseInt(e.target.value);
      bugSizeVal.innerText = `${this.bug.size}px`;
      localStorage.setItem('thud_bug_size', this.bug.size);
    });

    targetHitsInput.addEventListener('change', (e) => {
      this.targetHits = parseInt(e.target.value) || 5;
      localStorage.setItem('thud_target_hits', this.targetHits);
    });
  }

  pickNewBugTarget() {
    const margin = this.margin || 24;
    const padding = this.bug.size + 20;
    const minX = margin + padding;
    const maxX = this.canvas.width - margin - padding;
    const minY = margin + padding;
    const maxY = this.canvas.height - margin - padding;

    this.bug.targetX = minX + Math.random() * Math.max(10, (maxX - minX));
    this.bug.targetY = minY + Math.random() * Math.max(10, (maxY - minY));
    this.bug.targetAngle = Math.atan2(this.bug.targetY - this.bug.y, this.bug.targetX - this.bug.x) + (Math.PI / 2);
  }

  update(dt, margin) {
    this.margin = margin;
    if (this.gameWon) return;

    if (this.bug.speed <= 0) {
      // Bug is stopped for calibration
      return;
    }

    const dx = this.bug.targetX - this.bug.x;
    const dy = this.bug.targetY - this.bug.y;
    const dist = Math.hypot(dx, dy);

    this.bug.changeTargetTimer += dt;

    if (dist < 15 || this.bug.changeTargetTimer > 4000) {
      this.pickNewBugTarget();
      this.bug.changeTargetTimer = 0;
    } else {
      let angleDiff = this.bug.targetAngle - this.bug.angle;
      while (angleDiff < -Math.PI) angleDiff += Math.PI * 2;
      while (angleDiff > Math.PI) angleDiff -= Math.PI * 2;
      this.bug.angle += angleDiff * 0.1;

      const moveStep = this.bug.speed * (dt / 16.0);
      this.bug.x += Math.cos(this.bug.angle - Math.PI / 2) * moveStep;
      this.bug.y += Math.sin(this.bug.angle - Math.PI / 2) * moveStep;

      this.bug.legPhase += 0.2 * this.bug.speed;
    }
  }

  createBloodSplatter(x, y) {
    const droplets = [];
    const numDroplets = 12 + Math.floor(Math.random() * 16);
    for (let i = 0; i < numDroplets; i++) {
      const angle = Math.random() * Math.PI * 2;
      const dist = 10 + Math.random() * 45;
      droplets.push({
        x: x + Math.cos(angle) * dist,
        y: y + Math.sin(angle) * dist,
        r: 2 + Math.random() * 6
      });
    }

    this.bloodSplatters.push({
      x: x, y: y,
      coreRadius: 18 + Math.random() * 10,
      droplets: droplets,
      color: '#D00030', darkColor: '#800018',
      hitNum: this.totalHits
    });
  }

  onImpact(u, v, screenX, screenY) {
    if (this.gameWon) return { hit: false };

    const dx = screenX - this.bug.x;
    const dy = screenY - this.bug.y;
    const dist = Math.hypot(dx, dy);
    const HIT_RADIUS = Math.max(30, this.bug.size * 1.5);

    if (dist <= HIT_RADIUS) {
      // DIRECT HIT! SQUASH THE BUG!
      this.totalHits++;
      if (this.totalHits === 1) {
        this.gameStartTime = Date.now();
      }

      this.createBloodSplatter(this.bug.x, this.bug.y);

      if (this.totalHits >= this.targetHits) {
        this.gameWon = true;
        const elapsedSec = this.gameStartTime ? ((Date.now() - this.gameStartTime) / 1000).toFixed(1) : '0.0';
        return {
          hit: true,
          squashed: true,
          won: true,
          message: `🏆 YOU WIN! Squashed ${this.totalHits}/${this.targetHits} in ${elapsedSec}s!`
        };
      } else {
        this.pickNewBugTarget();
        if (this.bug.speed > 0) {
          this.bug.x = this.bug.targetX;
          this.bug.y = this.bug.targetY;
        }
        return {
          hit: true,
          squashed: true,
          won: false,
          message: `HIT! #${this.totalHits}`
        };
      }
    }

    return { hit: false, message: 'MISS' };
  }

  draw(ctx) {
    // 1. Render Blood Splatters
    for (const splat of this.bloodSplatters) {
      ctx.save();
      ctx.fillStyle = splat.color;
      ctx.shadowColor = splat.darkColor;
      ctx.shadowBlur = 10;

      ctx.beginPath();
      ctx.arc(splat.x, splat.y, splat.coreRadius, 0, Math.PI * 2);
      ctx.fill();

      for (const d of splat.droplets) {
        ctx.beginPath();
        ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.fillStyle = '#FFFFFF';
      ctx.font = 'bold 11px monospace';
      ctx.fillText(`#${splat.hitNum}`, splat.x - 8, splat.y + 4);
      ctx.restore();
    }

    // 2. Render Bug
    if (this.gameWon) return;

    ctx.save();
    ctx.translate(this.bug.x, this.bug.y);
    ctx.rotate(this.bug.angle);

    const s = this.bug.size / 28.0;

    // 6 Animated Legs
    ctx.strokeStyle = '#1a1a1a';
    ctx.lineWidth = Math.max(1.5, 3 * s);
    ctx.lineCap = 'round';
    const legSwing = Math.sin(this.bug.legPhase) * (12 * s);

    ctx.beginPath();
    ctx.moveTo(0, -5 * s); ctx.lineTo((-22 * s) + legSwing, -18 * s);
    ctx.moveTo(0, -5 * s); ctx.lineTo((22 * s) - legSwing, -18 * s);
    ctx.moveTo(0, 0); ctx.lineTo((-26 * s) - legSwing, 0);
    ctx.moveTo(0, 0); ctx.lineTo((26 * s) + legSwing, 0);
    ctx.moveTo(0, 5 * s); ctx.lineTo((-22 * s) + legSwing, 18 * s);
    ctx.moveTo(0, 5 * s); ctx.lineTo((22 * s) - legSwing, 18 * s);
    ctx.stroke();

    // Body
    ctx.fillStyle = '#222222';
    ctx.beginPath();
    ctx.ellipse(0, 0, 12 * s, 18 * s, 0, 0, Math.PI * 2);
    ctx.fill();

    // Head
    ctx.fillStyle = '#111111';
    ctx.beginPath();
    ctx.arc(0, -16 * s, 8 * s, 0, Math.PI * 2);
    ctx.fill();

    // Antennae
    ctx.strokeStyle = '#222222';
    ctx.lineWidth = Math.max(1, 2 * s);
    ctx.beginPath();
    ctx.moveTo(-4 * s, -20 * s); ctx.lineTo(-12 * s, -30 * s);
    ctx.moveTo(4 * s, -20 * s); ctx.lineTo(12 * s, -30 * s);
    ctx.stroke();

    // Red Eyes
    ctx.fillStyle = '#FF0033';
    ctx.beginPath();
    ctx.arc(-4 * s, -18 * s, Math.max(1.5, 2.5 * s), 0, Math.PI * 2);
    ctx.arc(4 * s, -18 * s, Math.max(1.5, 2.5 * s), 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }

  getStatsText() {
    return `🦟 SQUASHED: ${this.totalHits}/${this.targetHits}`;
  }
}
