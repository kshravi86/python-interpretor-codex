import Foundation

struct SampleSnippet: Identifiable {
    let id = UUID()
    let title: String
    let code: String
}

enum SnippetsCatalog {
    static let all: [SampleSnippet] = [
        SampleSnippet(title: "Hello + Loop", code: """
print('Hello from Python!')
for i in range(3):
    print(i)
"""),
        SampleSnippet(title: "FizzBuzz", code: """
for n in range(1, 21):
    s = ''
    if n % 3 == 0: s += 'Fizz'
    if n % 5 == 0: s += 'Buzz'
    print(s or n)
"""),
        SampleSnippet(title: "List Comprehension", code: """
squares = [n*n for n in range(10)]
print(squares)
"""),
        SampleSnippet(title: "Function + Recursion", code: """
def fib(n):
    return n if n < 2 else fib(n-1) + fib(n-2)

print([fib(i) for i in range(10)])
"""),
        SampleSnippet(title: "Dict + Loop", code: """
counts = {'apples': 2, 'bananas': 3}
for k, v in counts.items():
    print(k, v)
"""),
    ]
}

