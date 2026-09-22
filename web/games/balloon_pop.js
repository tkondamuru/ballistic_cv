// Modular Game: Balloon Pop
export default class BalloonPopGame {
  constructor() {
    this.name = "🎈 Balloon Pop";
    this.id = "balloon_pop";
    this.score = 0;
    this.poppedCount = 0;
    this.targetPops = 20;
    this.balloonSpeed = 1.5;
    this.combo = 1;
    this.lastPopTime = 0;
    this.gameWon = false;

    this.balloons = [];
    this.particles = [];
    this.floatingTexts = [];

    this.balloonColors = [
      { fill: '#ff4757', shine: '#ff6b81' }, // Red
      { fill: '#1e90ff', shine: '#70a1ff' }, // Blue
      { fill: '#2ed573', shine: '#7bed9f' }, // Green
      { fill: '#ffa502', shine: '#eccc68' }, // Yellow/Orange
      { fill: '#9b59b6', shine: '#be2edd' }, // Purple
    ];
  }

  init(canvas, margin) {
    this.canvas = canvas;
    this.margin = margin || 24;
    this.score = 0;
    this.poppedCount = 0;
    this.combo = 1;
    this.lastPopTime = 0;
    this.gameWon = false;
    this.balloons = [];
    this.particles = [];
    this.floatingTexts = [];

    const savedTarget = localStorage.getItem('thud_balloon_target');
    if (savedTarget !== null) {
      this.targetPops = parseInt(savedTarget) || 20;
    }

    const savedSpeed = localStorage.getItem('thud_balloon_speed');
    if (savedSpeed !== null) {
      this.balloonSpeed = parseFloat(savedSpeed) || 1.5;
    }
  }

  renderOptions(container) {
    container.innerHTML = `
      <div class="input-group" title="Balloon Float Speed">
        <label>Float Spd:</label>
        <input type="range" id="balloonSpeedSlider" min="0.5" max="4.0" step="0.5" value="${this.balloonSpeed}" style="width: 45px;">
        <span id="balloonSpeedVal" class="val-readout">${this.balloonSpeed}</span>
      </div>
      <div class="input-group" title="Target Pops Goal">
        <label>Target Pops:</label>
        <input type="number" id="targetPopsInput" value="${this.targetPops}" min="5" max="100" style="width: 42px;">
      </div>
    `;

    const balloonSpeedSlider = container.querySelector('#balloonSpeedSlider');
    const balloonSpeedVal = container.querySelector('#balloonSpeedVal');
    const targetPopsInput = container.querySelector('#targetPopsInput');

    balloonSpeedSlider.addEventListener('input', (e) => {
      this.balloonSpeed = parseFloat(e.target.value);
      balloonSpeedVal.innerText = this.balloonSpeed;
      localStorage.setItem('thud_balloon_speed', this.balloonSpeed);
    });

    targetPopsInput.addEventListener('change', (e) => {
      this.targetPops = parseInt(e.target.value) || 20;
      localStorage.setItem('thud_balloon_target', this.targetPops);
    });
  }

  spawnBalloon() {
    const margin = this.margin || 24;
    const radius = 28 + Math.random() * 16;
    const isGolden = Math.random() < 0.12;
    const isBomb = !isGolden && Math.random() < 0.08;

    const minX = margin + radius;
    const maxX = Math.max(minX + 20, this.canvas.width - margin - radius);

    this.balloons.push({
      x: minX + Math.random() * (maxX - minX),
      y: this.canvas.height + radius + 10,
      radius: radius,
      speedY: (1.2 + Math.random() * 1.8) * (this.balloonSpeed / 1.5),
      swayAmp: 15 + Math.random() * 25,
      swayFreq: 0.02 + Math.random() * 0.03,
      swayPhase: Math.random() * Math.PI * 2,
      color: isGolden ? { fill: '#ffd700', shine: '#fff' } : (isBomb ? { fill: '#2f3542', shine: '#747d8c' } : this.balloonColors[Math.floor(Math.random() * this.balloonColors.length)]),
      isGolden: isGolden,
      isBomb: isBomb,
      popped: false
    });
  }

  update(dt, margin) {
    this.margin = margin || 24;
    if (this.gameWon) return;

    while (this.balloons.length < 7) {
      this.spawnBalloon();
    }

    const timeScale = dt / 16.0;

    for (let i = this.balloons.length - 1; i >= 0; i--) {
      const b = this.balloons[i];
      b.y -= b.speedY * timeScale;
      b.swayPhase += b.swayFreq * timeScale;
      b.x += Math.sin(b.swayPhase) * 0.8 * timeScale;

      if (b.y < -b.radius * 2) {
        this.balloons.splice(i, 1);
      }
    }
  }

  createExplosion(x, y, color, count = 25) {
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 2 + Math.random() * 7;
      this.particles.push({
        x: x, y: y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        radius: 3 + Math.random() * 4,
        color: color,
        alpha: 1.0,
        decay: 0.02 + Math.random() * 0.03
      });
    }
  }

  createFloatingText(x, y, text, color = '#38bdf8') {
    this.floatingTexts.push({
      x: x, y: y,
      text: text,
      color: color,
      alpha: 1.0,
      vy: -1.5
    });
  }

  onImpact(u, v, screenX, screenY) {
    if (this.gameWon) return { hit: false };

    let hitAny = false;
    const now = Date.now();
    if (now - this.lastPopTime < 2000) this.combo++;
    else this.combo = 1;

    for (let i = this.balloons.length - 1; i >= 0; i--) {
      const b = this.balloons[i];
      const dist = Math.hypot(screenX - b.x, screenY - b.y);

      if (dist <= b.radius + 35) {
        hitAny = true;
        this.lastPopTime = now;
        this.poppedCount++;

        let points = (b.isGolden ? 300 : (b.isBomb ? 50 : 100)) * this.combo;
        this.score += points;

        this.createExplosion(b.x, b.y, b.color.fill, b.isBomb ? 50 : 25);
        this.createFloatingText(b.x, b.y, `+${points} ${this.combo > 1 ? this.combo + 'x Combo!' : ''}`, b.isGolden ? '#ffd700' : '#38bdf8');

        if (b.isBomb) {
          for (let j = this.balloons.length - 1; j >= 0; j--) {
            if (i !== j && Math.hypot(b.x - this.balloons[j].x, b.y - this.balloons[j].y) < 160) {
              this.createExplosion(this.balloons[j].x, this.balloons[j].y, this.balloons[j].color.fill);
              this.balloons.splice(j, 1);
              this.poppedCount++;
            }
          }
        }

        this.balloons.splice(i, 1);

        if (this.poppedCount >= this.targetPops) {
          this.gameWon = true;
          return {
            hit: true,
            won: true,
            message: `🎈 POP MASTER! Popped ${this.poppedCount} balloons! Score: ${this.score}`
          };
        }

        return {
          hit: true,
          won: false,
          message: `POP! ${this.combo}x`
        };
      }
    }

    return { hit: false, message: 'MISS' };
  }

  draw(ctx) {
    for (const b of this.balloons) {
      ctx.save();
      ctx.beginPath();
      ctx.ellipse(b.x, b.y, b.radius * 0.85, b.radius, 0, 0, Math.PI * 2);
      ctx.fillStyle = b.color.fill;
      ctx.shadowColor = b.color.fill;
      ctx.shadowBlur = b.isGolden ? 20 : 10;
      ctx.fill();

      ctx.beginPath();
      ctx.ellipse(b.x - b.radius * 0.3, b.y - b.radius * 0.3, b.radius * 0.25, b.radius * 0.35, -Math.PI / 4, 0, Math.PI * 2);
      ctx.fillStyle = b.color.shine;
      ctx.fill();

      ctx.beginPath();
      ctx.moveTo(b.x, b.y + b.radius);
      ctx.lineTo(b.x - 4, b.y + b.radius + 6);
      ctx.lineTo(b.x + 4, b.y + b.radius + 6);
      ctx.closePath();
      ctx.fillStyle = b.color.fill;
      ctx.fill();

      ctx.beginPath();
      ctx.moveTo(b.x, b.y + b.radius + 6);
      ctx.quadraticCurveTo(b.x + Math.sin(b.swayPhase * 2) * 10, b.y + b.radius + 25, b.x, b.y + b.radius + 45);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
      ctx.lineWidth = 1.5;
      ctx.stroke();

      ctx.restore();
    }

    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx; p.y += p.vy;
      p.alpha -= p.decay;
      if (p.alpha <= 0) { this.particles.splice(i, 1); continue; }

      ctx.save();
      ctx.globalAlpha = p.alpha;
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    for (let i = this.floatingTexts.length - 1; i >= 0; i--) {
      const t = this.floatingTexts[i];
      t.y += t.vy;
      t.alpha -= 0.02;
      if (t.alpha <= 0) { this.floatingTexts.splice(i, 1); continue; }

      ctx.save();
      ctx.globalAlpha = t.alpha;
      ctx.fillStyle = t.color;
      ctx.font = '900 18px system-ui';
      ctx.fillText(t.text, t.x - 20, t.y);
      ctx.restore();
    }
  }

  getStatsText() {
    return `🎈 POPPED: ${this.poppedCount}/${this.targetPops} | SCORE: ${this.score} | COMBO: ${this.combo}x`;
  }
}
