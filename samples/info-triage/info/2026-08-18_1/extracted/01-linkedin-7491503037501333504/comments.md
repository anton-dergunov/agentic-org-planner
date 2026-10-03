## Other comments

**Dev Suthar** — Curious about your implementation philosophy: when reproducing newer architectures, how do you decide where to stop? Do you optimize for paper-faithful implementations, or do you incorporate community-discovered improvements when they better reflect how these models are actually trained and deployed today?

**Gabriel dos Santos** — I really like this project because you make the gap between  understanding the theory and actually implementing it smaller.
Implementing attention, KV cache, GQA, MoE, or even the training loop from scratch forces you to understand what is actually happening under the hood. 100k stars is a huge milestone, but I think the number of people who learned something from the repository is even more interesting.

**Ilya Kalimulin, Ph.D.** — Thank you, Sebastian, for such a great repo. How do you think, is there a place for something more: e.g., an inference server from scratch, an agent from scratch, additional architectures, etc?

**Fanus Arefaine** — This is so well deserved, Sebastian Raschka, PhD. Build a Large Language Model (From Scratch) was the book that finally made LLM architecture click for me and helped motivate me to build QAL

And while I’m already eyeing Build a Reasoning Model (From Scratch), I gotta ask ya

What's the next book?  😁

**Siva Kandula** — Most infra teams are currently scrambling to retrofit cross-layer KV sharing and MLA into their serving stacks so having bare-bones PyTorch to step through is a massive timesaver. Getting to actually print and debug the tensor shapes locally beats trying to reverse-engineer a dense official repository.

**Alexey Gililov** — Well deserved. The real achievement is not just the breadth of architectures; it is preserving the path from paper notation to tensor shapes, KV-cache behavior, and training trade-offs without burying it under framework abstractions. That makes the repo useful both for learning and for sanity-checking production implementations. At 100k stars, it has crossed from repository into public infrastructure.

**Sarvex Jatasra** — Sparse attention is the strange case in a from-scratch repo. A readable version computes the full score matrix and then masks it, which reproduces the output exactly while saving nothing at all. The savings live in the kernel. When you added DeepSeek Sparse Attention, did you treat that as a limit worth naming, or did you find a selection step that stays legible and still runs on a laptop?

**Nenad Djordjevic** — Building from scratch isn't academic nostalgia — it's the fastest way to develop intuition for where the real bottlenecks live. Looking forward to the small LLM project.

**Vitalii Serbyn** — picking through the DeepSeek Sparse Attention implementation is where i'd spend the weekend, since most repos still hand-wave the indexer/selection step.
  for the next book i'd go Build a Reasoning Model from Scratch first, RL from scratch after that once GRPO clicks on top of the base transformer code.

**Dawood Mallick** — But still the memory efficiency was not on the peak... When we resonate the coding it was not that way that we are required...
