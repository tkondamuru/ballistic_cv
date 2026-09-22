// Modular Game: Math Blaster Quiz
export default class MathBlasterGame {
  constructor() {
    this.name = "🧮 Math Blaster Quiz";
    this.id = "math_blaster";
    this.currentAnswer = 0;
    this.questionText = '';
    this.targetBubbles = [];
    this.particles = [];
    this.score = 0;
    this.streak = 0;
    this.bubbleRadius = 38;

    this.BUBBLE_COLORS = ['#ec4899', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6'];
  }

  init(canvas, margin) {
    this.canvas = canvas;
    this.margin = margin || 24;
    this.score = 0;
    this.streak = 0;
    this.particles = [];

    const savedRadius = localStorage.getItem('thud_math_bubble_radius');
    if (savedRadius !== null) this.bubbleRadius = parseInt(savedRadius) || 38;

    this.generateMathQuestion();
  }

  renderOptions(container) {
    container.innerHTML = `
      <div class="input-group" title="Bubble Target Size">
        <label>Bubble Size:</label>
        <input type="range" id="bubbleSizeSlider" min="25" max="55" value="${this.bubbleRadius}" style="width: 45px;">
        <span id="bubbleSizeVal" class="val-readout">${this.bubbleRadius}px</span>
      </div>
      <button id="nextQuestionBtn" class="btn" style="background:#475569; padding: 3px 8px; font-size: 11px;">Skip ➔</button>
    `;

    const sizeSlider = container.querySelector('#bubbleSizeSlider');
    const sizeVal = container.querySelector('#bubbleSizeVal');
    const nextBtn = container.querySelector('#nextQuestionBtn');

    sizeSlider.addEventListener('input', (e) => {
      this.bubbleRadius = parseInt(e.target.value);
      sizeVal.innerText = `${this.bubbleRadius}px`;
      localStorage.setItem('thud_math_bubble_radius', this.bubbleRadius);
      this.targetBubbles.forEach(b => b.radius = this.bubbleRadius);
    });

    nextBtn.addEventListener('click', () => {
      this.generateMathQuestion();
    });
  }

  generateMathQuestion() {
    const isMultiplication = Math.random() < 0.35;
    let a, b, answer, operator;

    if (isMultiplication) {
      a = 2 + Math.floor(Math.random() * 8);
      b = 2 + Math.floor(Math.random() * 8);
      operator = '×';
      answer = a * b;
    } else {
      a = 5 + Math.floor(Math.random() * 20);
      b = 3 + Math.floor(Math.random() * 20);
      operator = '+';
      answer = a + b;
    }

    this.currentAnswer = answer;
    this.questionText = `${a} ${operator} ${b} = ?`;

    this.targetBubbles = [];
    const margin = this.margin || 24;
    const choices = [answer];

    while (choices.length < 5) {
      const offset = (Math.floor(Math.random() * 10) + 1) * (Math.random() < 0.5 ? 1 : -1);
      const wrongChoice = Math.max(1, answer + offset);
      if (!choices.includes(wrongChoice)) choices.push(wrongChoice);
    }

    choices.sort(() => Math.random() - 0.5);

    const zoneWidth = (this.canvas.width - 2 * margin) / 5;
    for (let i = 0; i < 5; i++) {
      this.targetBubbles.push({
        x: margin + i * zoneWidth + zoneWidth / 2,
        y: this.canvas.height * 0.45 + (Math.random() * 120 - 60),
        val: choices[i],
        radius: this.bubbleRadius,
        color: this.BUBBLE_COLORS[i % this.BUBBLE_COLORS.length],
        vy: Math.random() < 0.5 ? 0.8 : -0.8
      });
    }
  }

  createCelebration(x, y) {
    for (let i = 0; i < 40; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 3 + Math.random() * 8;
      this.particles.push({
        x: x, y: y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        radius: 4 + Math.random() * 5,
        color: this.BUBBLE_COLORS[Math.floor(Math.random() * this.BUBBLE_COLORS.length)],
        alpha: 1.0,
        decay: 0.02
      });
    }
  }

  update(dt, margin) {
    this.margin = margin || 24;
    const timeScale = dt / 16.0;

    for (const b of this.targetBubbles) {
      b.y += b.vy * timeScale;
      if (b.y < this.canvas.height * 0.3 || b.y > this.canvas.height * 0.65) b.vy *= -1;
    }

    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx; p.y += p.vy; p.alpha -= p.decay;
      if (p.alpha <= 0) { this.particles.splice(i, 1); }
    }
  }

  onImpact(u, v, screenX, screenY) {
    let hitAny = false;
    for (let i = 0; i < this.targetBubbles.length; i++) {
      const b = this.targetBubbles[i];
      if (Math.hypot(screenX - b.x, screenY - b.y) <= b.radius + 30) {
        hitAny = true;
        if (b.val === this.currentAnswer) {
          this.score += 100 + (this.streak * 20);
          this.streak++;
          this.createCelebration(b.x, b.y);
          setTimeout(() => this.generateMathQuestion(), 1200);

          return {
            hit: true,
            won: false,
            message: 'CORRECT! 🎉'
          };
        } else {
          this.streak = 0;
          return {
            hit: false,
            won: false,
            message: 'TRY AGAIN!'
          };
        }
      }
    }

    return { hit: false, message: 'MISS' };
  }

  draw(ctx) {
    ctx.save();
    ctx.fillStyle = '#ffffff';
    ctx.font = '900 42px system-ui';
    ctx.textAlign = 'center';
    ctx.shadowColor = 'rgba(56, 189, 248, 0.8)';
    ctx.shadowBlur = 15;
    ctx.fillText(this.questionText, this.canvas.width / 2, this.canvas.height * 0.22);
    ctx.restore();

    for (const b of this.targetBubbles) {
      ctx.save();
      ctx.beginPath();
      ctx.arc(b.x, b.y, b.radius, 0, Math.PI * 2);
      ctx.fillStyle = b.color;
      ctx.shadowColor = b.color;
      ctx.shadowBlur = 16;
      ctx.fill();

      ctx.fillStyle = '#ffffff';
      ctx.font = '900 24px system-ui';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(b.val, b.x, b.y);
      ctx.restore();
    }

    for (const p of this.particles) {
      ctx.save();
      ctx.globalAlpha = p.alpha;
      ctx.fillStyle = p.color;
      ctx.beginPath(); ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }
  }

  getStatsText() {
    return `🧮 MATH: ${this.questionText} | SCORE: ${this.score} | STREAK: ${this.streak}🔥`;
  }
}
