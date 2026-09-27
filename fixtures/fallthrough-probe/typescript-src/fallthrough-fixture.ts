function callA(): void {
}

function callB(): void {
}

function callDefault(): void {
}

export function exerciseFallthrough(mode: number): void {
  switch (mode) {
    case 1:
      callA();
    case 2:
      callB();
      break;
    default:
      callDefault();
  }
}
