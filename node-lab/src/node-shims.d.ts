declare module "node:child_process" {
  export function exec(command: string): void;
}

declare const process: {
  argv: string[];
};
