# ConcurrencyRecipes
Practical solutions to problems with Swift Concurrency

Swift Concurrency can be really hard to use. I thought it could be handy to document and share solutions and hazards you might face along the way. I am **absolutely not** saying this is comprehensive, or that the solutions presents are great. I'm learning too. Contributions are very welcome, especially for problems!

## Hazards

Quick definitions for the hazards referenced throughout the recipes:

- Timing: More than one option is available, but can affect when events actually occur.
- Ordering: Unstructured tasks means ordering is up to the caller. Think carefully about dependencies, multiple invocations, and cancellation.
- Lack of Caller Control: definitions always control actor context. This is different from other threading models, and you cannot alter definitions you do not control.
- Sendability: types that cross isolation domains must be sendable. This isn't always easy, and for types you do not control, not possible.
- Blocking: Swift concurrency uses a fixed-size thread pool. Tying up background threads can lead lag and even deadlock.
- Availability: Concurrency is evolving rapidly, and some APIs require the latest SDK.
- Async virality: Making a function async affects all its callsites. This can result in a large number of changes, each of which could, itself, affect subsequence callsites.

## Table of Contents

- [Creating an Async Context](Recipes/AsyncContext.md)
- [Using Protocols](Recipes/Protocols.md)
- [Sendability](Recipes/Sendability.md)

## Contributing and Collaboration

I'd love to hear from you! Get in touch via [mastodon](https://mastodon.social/@mattiem), an issue, or a pull request.

I prefer collaboration, and would love to find ways to work together if you have a similar project.

By participating in this project you agree to abide by the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).
