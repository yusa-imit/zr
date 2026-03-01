use criterion::{black_box, criterion_group, criterion_main, Criterion};

pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

pub fn multiply(a: i32, b: i32) -> i32 {
    a * b
}

fn criterion_benchmark(c: &mut Criterion) {
    c.bench_function("add", |b| b.iter(|| add(black_box(20), black_box(30))));
    c.bench_function("multiply", |b| {
        b.iter(|| multiply(black_box(20), black_box(30)))
    });
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
