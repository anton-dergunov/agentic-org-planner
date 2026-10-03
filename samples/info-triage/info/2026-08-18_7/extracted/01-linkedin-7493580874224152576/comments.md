## Author comments

**Maxime Labonne** — https://arxiv.org/abs/2603.07267


## Other comments

**Sarvex Jatasra** — Hiding the trace clearly does not stop transfer, but the $173 is buying less than it looks.

In Table 4, the control row that never queries GPT-5.4 mini at all, fine-tuning the 7B student on R1's own traces, already hits the identical 43.7 on JEEBench and 33.2 on LiveCodeBench against inversion's 28.9. Only MATH500 moves.

Appendix A says why: Table 6 puts GPT-5.4 mini below R1 on all three benchmarks. Show me a row where querying the victim beats the free surrogate on more than one benchmark and I fold.

**Soumik Mukherjee** — The finding about reconstructed traces beating DeepSeek-R1's actual traces is the real headline. Real human (and AI) reasoning is messy—full of dead ends, backtracking, and false starts. Reverse-engineering the steps from the correct answer effectively creates a 'sanitized' rationalization path !

**Sallyann Della Casa** — I'm really curious to see how this research impacts the development of more secure reasoning models, especially given the potential for reconstructed traces to outperform actual ones in certain cases.

**Jahanzaib A.** — Maxime Labonne $173 to rebuild traces the target spent millions training is the number that should worry every lab. and the reconstruction beating real R1 traces because it skips the wandering is a genuinely uncomfortable finding.

**Dr. Sundaraparipurnan Narayanan** — Maxime Labonne thanks for the idea. It’s a useful and powerful idea. And may also avoid exposures regarding model distillation or exploitation.

I think there’s an important assumption here: that a reasoning trace is essentially a function of the input and the final output. This may not be true.

Reasoning doesn’t always map cleanly to the outcome in IRW. A model can reason about a risk, explore alternatives, or identify a concern, and still ultimately take an action that doesn’t fully reflect that reasoning. Some considerations may be overridden by higher-level objectives, policies, uncertainty, or other parts of the system.

The reasoning itself can also depend on latent state, intermediate representations, tool calls, retrieved information, prior context, exploration, and paths that are ultimately discarded. Two identical input/output pairs can therefore correspond to very different reasoning processes.  A plausible explanation not necessarily a reconstruction of the reasoning that actually produced it.

So I think the more interesting question is:

How much of the actual reasoning process is identifiable from the input/output channel alone?

**Refat Ametov** — Anti-distillation techniques that poison the exposed trace don't help here because inversion never reads it. Rate limiting and query detection are the practical options, but both assume you can distinguish attack traffic from legitimate use at 10k queries over an unspecified time window, and that distinction gets harder as the attack gets cheaper. The more durable finding is the cost asymmetry: the inverter can be far weaker than the target, which means the cost to mount this attack will keep dropping as open models improve.

**Johann Frederik Machemer** — Maxime Labonne how much does the quality of the synthetic traces differ when you had summaries during training compared to having no summaries from the API? And what difference does that make for the benchmarks on the then fine tuned model?

**Jay Gandhi** — Maxime Labonne The deeper lesson is that reasoning privacy cannot depend on hiding traces alone. Observable outputs can still reveal structure when the right inversion methods exist.

**Aaron M.** — The inverted traces beating the target's actual reasoning is the wildest part of this. Means the defense can't just watermark the summaries either, since the attack never touches them. The anti-distillation angle on the final-answer channel feels like the only real lever left.
