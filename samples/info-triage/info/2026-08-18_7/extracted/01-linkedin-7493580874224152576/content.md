# 🥷 How to Steal Reasoning Without Reasoning Traces

- Author: Maxime Labonne
- Published: 2026-08-13T08:15:04.660Z
- URL: https://www.linkedin.com/posts/maxime-labonne_how-to-steal-reasoning-without-reasoning-share-7493580874224152576-kiKE/

🥷 How to Steal Reasoning Without Reasoning Traces

Reasoning models keep their internal traces private and return only a final answer with a short summary. That is meant to stop competitors from distilling them. This paper from Cornell Tech shows it doesn't work: the answers alone are enough to rebuild usable traces.

→ Copying a model's answers doesn't transfer its reasoning. A 7B model drops from 71.2% to 68.4% on MATH500, and to 19.8% when you also feed it the short summaries the API returns.

→ So write the missing reasoning yourself. Train a model to go from question and answer back to the steps that connect them, using an open model's traces as examples. Then run it on the target's answers and fine-tune the student on what it invents.

→ That one change takes the same student from 68.4% to 76.0% on MATH500, and from 27.6% to 43.7% on JEEBench. The 10k queries to the target cost $173.

→ Writing steps is much easier than finding them, so the attacker's model can be far weaker than the target. Traces from a 1.5B model teach a student almost nothing directly (19.7% on JEEBench), but the same traces used to train the inverter get it to 31.6%.

→ A clean invention can teach better than the real thing! Against DeepSeek-R1, students trained on reconstructed traces beat students trained on R1's actual ones. Real reasoning wanders and backtracks, while a reconstruction already knows where it lands.

One caveat: the attack should matter most when the target is far beyond any open model, and that is the case they can't test. The defense implication still stands. Anti-distillation sampling and similar methods poison the exposed trace, but inversion never reads it. The student only ever sees the target's final answers, so I wonder whether a text watermark can survive a channel that narrow (hello Claude).
