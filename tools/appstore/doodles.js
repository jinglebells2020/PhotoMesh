// Hand-drawn feeling circuit symbols, one per name, on a 100 × 100 box.
window.DOODLES = {
  resistor: `<path d="M2 50 H20 L28 30 L40 70 L52 30 L64 70 L76 30 L84 50 H98"/>`,
  capacitor: `<path d="M2 50 H40 M40 24 V76 M60 24 V76 M60 50 H98"/>`,
  inductor: `<path d="M2 50 H14 A8 8 0 0 1 30 50 A8 8 0 0 1 46 50 A8 8 0 0 1 62 50 A8 8 0 0 1 78 50 H98"/>`,
  battery: `<path d="M2 50 H38 M38 20 V80 M52 34 V66 M52 50 H98 M24 16 V30 M17 23 H31"/>`,
  ground: `<path d="M50 6 V44 M18 44 H82 M30 60 H70 M42 76 H58"/>`,
  node: `<path d="M50 50 H96 M50 50 L8 14 M50 50 L8 86"/><circle cx="50" cy="50" r="8" fill="currentColor" stroke="none"/>`,
  arrow: `<path d="M6 58 H80 M62 40 L82 58 L62 76"/>`,
  switch: `<path d="M2 62 H28 M30 60 L70 28 M72 62 H98"/><circle cx="29" cy="62" r="5" fill="currentColor" stroke="none"/><circle cx="71" cy="62" r="5" fill="currentColor" stroke="none"/>`,
  lamp: `<circle cx="50" cy="50" r="30"/><path d="M29 29 L71 71 M71 29 L29 71 M2 50 H20 M80 50 H98"/>`,
  loop: `<path d="M22 12 H36 L42 22 L50 2 L58 22 L64 12 H78 Q90 12 90 24 V78 Q90 90 78 90 H22 Q10 90 10 78 V24 Q10 12 22 12 Z"/><path d="M40 52 L50 62 L60 52"/>`,
  plus: `<path d="M50 18 V82 M18 50 H82"/>`,
  omega: `<text x="50" y="78" text-anchor="middle" font-size="86" font-weight="700" font-family="Inter, sans-serif" fill="currentColor" stroke="none">Ω</text>`,
  volt: `<text x="50" y="78" text-anchor="middle" font-size="84" font-weight="700" font-family="Inter, sans-serif" fill="currentColor" stroke="none">V</text>`,
  current: `<path d="M8 70 H70 M56 56 L72 70 L56 84"/><text x="26" y="44" text-anchor="middle" font-size="44" font-weight="700" font-style="italic" font-family="Inter, sans-serif" fill="currentColor" stroke="none">I</text>`,
  sine: `<path d="M2 50 C18 10, 34 10, 50 50 S82 90, 98 50"/>`,
  dots: `<circle cx="20" cy="50" r="7" fill="currentColor" stroke="none"/><circle cx="50" cy="50" r="7" fill="currentColor" stroke="none"/><circle cx="80" cy="50" r="7" fill="currentColor" stroke="none"/>`,
};
