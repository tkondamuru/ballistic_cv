// Modular Game: Target Bullseye Trainer
export default class BullseyeGame {
  constructor() {
    this.name = "🎯 Target Bullseye";
    this.id = "bullseye";
    this.score = 0;
    this.totalThuds = 0;
    this.bullseyes = 0;
    this.totalErrorDist = 0;
    this.targetScale = 1.0;

    this.hitHistory = [];
    this.targetCenter = { x: 0, y: 0 };
    this.baseRingRadii = [35, 80, 140, 210, 290];
    this.ringRadii = [...this.baseRingRadii];
    this.ringScores = [100, 75, 50, 25, 10];
  }

  init(canvas, margin) {
    this.canvas = canvas;
    this.margin = margin || 24;
    this.score = 0;
    this.totalThuds = 0;
    this.bullseyes = 0;
    this.totalErrorDist = 0;
    this.hitHistory = [];
    this.targetCenter = { x: this.canvas.width / 2, y: this.canvas.height / 2 };

    const savedScale = localStorage.getItem('thud_bullseye_scale');
    if (savedScale !== null) {
      this.targetScale = parseFloat(savedScale) || 1.0;
      this.updateRingRadii();
    }
  }

  updateRingRadii() {
    this.ringRadii = this.baseRingRadii.map(r => r * this.targetScale);
  }

  renderOptions(container) {
    container.innerHTML = `
      <div class="input-group" title="Target Scale Factor">
        <label>Target Scale:</label>
        <input type="range" id="targetScaleSlider" min="0.5" max="1.5" step="0.1" value="${this.targetScale}" style="width: 45px;">
        <span id="targetScaleVal" class="val-readout">${this.targetScale}x</span>
      </div>
      <button id="clearHistoryBtn" class="btn" style="background:#475569; padding: 3px 8px; font-size: 11px;">Clear</button>
    `;

    const scaleSlider = container.querySelector('#targetScaleSlider');
    const scaleVal = container.querySelector('#targetScaleVal');
    const clearBtn = container.querySelector('#clearHistoryBtn');

    scaleSlider.addEventListener('input', (e) => {
      this.targetScale = parseFloat(e.target.value);
      scaleVal.innerText = `${this.targetScale}x`;
      localStorage.setItem('thud_bullseye_scale', this.targetScale);
      this.updateRingRadii();
    });

    clearBtn.addEventListener('click', () => {
      this.score = 0;
      this.totalThuds = 0;
      this.bullseyes = 0;
      this.totalErrorDist = 0;
      this.hitHistory = [];
    });
  }

  update(dt, margin) {
    this.margin = margin || 24;
    this.targetCenter = { x: this.canvas.width / 2, y: this.canvas.height / 2 };
  }

  onImpact(u, v, screenX, screenY) {
    this.totalThuds++;
    const distFromCenter = Math.hypot(screenX - this.targetCenter.x, screenY - this.targetCenter.y);
    this.totalErrorDist += distFromCenter;

    let pts = 0;
    if (distFromCenter <= this.ringRadii[0]) { pts = 100; this.bullseyes++; }
    else if (distFromCenter <= this.ringRadii[1]) pts = 75;
    else if (distFromCenter <= this.ringRadii[2]) pts = 50;
    else if (distFromCenter <= this.ringRadii[3]) pts = 25;
    else if (distFromCenter <= this.ringRadii[4]) pts = 10;

    this.score += pts;

    this.hitHistory.push({
      num: this.totalThuds,
      x: screenX,
      y: screenY,
      dist: Math.round(distFromCenter),
      pts: pts
    });

    return {
      hit: pts > 0,
      won: false,
      message: pts > 0 ? `+${pts} PTS (${Math.round(distFromCenter)}px)` : 'MISS'
    };
  }

  draw(ctx) {
    const colors = ['#ef4444', '#ffffff', '#3b82f6', '#000000', '#f59e0b'];
    for (let i = this.ringRadii.length - 1; i >= 0; i--) {
      ctx.beginPath();
      ctx.arc(this.targetCenter.x, this.targetCenter.y, this.ringRadii[i], 0, Math.PI * 2);
      ctx.fillStyle = colors[i];
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(this.targetCenter.x - 20, this.targetCenter.y); ctx.lineTo(this.targetCenter.x + 20, this.targetCenter.y);
    ctx.moveTo(this.targetCenter.x, this.targetCenter.y - 20); ctx.lineTo(this.targetCenter.x, this.targetCenter.y + 20);
    ctx.stroke();

    for (const h of this.hitHistory) {
      ctx.save();
      ctx.beginPath();
      ctx.arc(h.x, h.y, 8, 0, Math.PI * 2);
      ctx.fillStyle = h.pts === 100 ? '#ffd700' : '#22d3ee';
      ctx.shadowColor = ctx.fillStyle;
      ctx.shadowBlur = 10;
      ctx.fill();

      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 1.5;
      ctx.stroke();

      ctx.fillStyle = '#ffffff';
      ctx.font = 'bold 11px monospace';
      ctx.fillText(`#${h.num} (+${h.pts})`, h.x + 12, h.y + 4);
      ctx.restore();
    }
  }

  getStatsText() {
    const avgErr = this.totalThuds > 0 ? Math.round(this.totalErrorDist / this.totalThuds) : 0;
    return `🎯 SCORE: ${this.score} | THUDS: ${this.totalThuds} | BULLSEYES: ${this.bullseyes} | AVG ERR: ${avgErr}px`;
  }
}
