export function greet(name: string): string {
  return `Hello, ${name}!`;
}

export function add(a: number, b: number): number {
  return a + b;
}

export function main(): void {
  console.log(greet('World'));
  console.log(`2 + 3 = ${add(2, 3)}`);
}

// Run main if this is the entry point
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
