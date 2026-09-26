interface Gateway {
  load(value: string): string;
}

function a(value: string | null): boolean {
  return value !== null;
}

function b(value: string): boolean {
  return value.length > 1;
}

function c(value: string): boolean {
  return value.startsWith("x");
}

function nested(value: string | null): string {
  return value === null ? "" : value.trim();
}

export function exerciseStructuralProbe(
  items: string[],
  mode: number,
  gateway: Gateway
): string {
  let value = nested(items[0]);

  if (a(value) && (b(value) || c(value))) {
    value = nested(value);
  } else {
    value = nested("else");
  }

  switch (mode) {
    case 1:
      value = nested("one");
      break;
    case 2:
      return gateway.load(value);
    default:
      value = nested("default");
  }

  const selected = mode > 0 ? gateway.load(value) : nested(value);

  value = nested(value) + nested(value);

  for (let i = 0; i < items.length; i++) {
    if (i === 1) {
      continue;
    }
    if (i > 3) {
      break;
    }
    value = nested(items[i]);
  }

  for (const item of items) {
    value = nested(item);
  }

  while (a(value)) {
    value = nested(value);
    break;
  }

  try {
    if (selected === null) {
      throw new Error("selected");
    }
    value = gateway.load(selected);
  } catch (error) {
    value = nested(String(error));
  } finally {
    nested("finally");
  }

  if (value.length === 0) {
    return "empty";
  }

  return value;
}
