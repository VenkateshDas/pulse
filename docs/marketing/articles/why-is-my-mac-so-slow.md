# Why is my Mac slow? Check CPU, memory and storage before changing anything

By Pulse · Sources reviewed 2 November 2026

Switching apps takes longer than it should. A document stalls when you scroll. Activity Monitor shows a process at the top of the list, but should you quit it?

Start with **CPU activity, Memory Pressure and available storage while the slowdown is happening**. These checks can help you choose what to investigate. Apple lists memory demands, limited startup-disk space and app compatibility among the possible causes of a slow Mac. [Apple’s slowdown checklist](https://support.apple.com/en-mide/guide/mac-help/mchlp1731/27/mac/27)

You can do every check below with built-in Mac tools. Save open work before quitting apps.

## First, choose a task you can try again

Describe the slowdown in one sentence: “Switching from my browser to my document takes several seconds,” for example. Keep that action for your comparison after each change. If only one website stalls, record that too; it is a narrower problem than every app becoming unresponsive.

Open **Finder → Applications → Utilities → Activity Monitor**. Choose **View → All Processes** and clear the search field so an old filter does not hide relevant processes. Click a column heading to sort; click again if the largest values are at the bottom. [Apple’s process-view instructions](https://support.apple.com/en-ng/guide/activity-monitor/actmntr1001/mac)

Return to the task that feels slow and watch several updates. Our suggested approach is to change one thing, then repeat that task. It gives you a useful comparison without making several changes whose effects you cannot separate.

## Check whether CPU activity fits the work

Select **CPU** and sort by **% CPU**, largest first. At the bottom, **User** shows CPU capacity used by your apps and their processes, **System** shows capacity used by macOS processes, and **Idle** shows unused capacity. For activity over time, choose **Window → CPU History**. [Apple’s CPU guide](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac)

Look at the app names as well as the numbers. Apple notes that calculation-intensive apps use more processor capacity. If an app is busy doing work you requested, the reading may fit the task. If an app you no longer need stays busy while your work stalls, it is worth investigating. Being first in the list does not establish a fault.

Save and quit that recognised app normally, then retry the slow action. If it improves, you have a lead. If it does not, avoid working down the list and quitting everything in turn.

For an unfamiliar process, double-click its row for details. **View → All Processes, Hierarchically** can show parent and child processes. Activity Monitor includes background and system processes as well as visible apps; an unfamiliar name alone is not evidence of trouble. [Apple’s process guide](https://support.apple.com/en-ng/guide/activity-monitor/actmntr1001/mac)

### Quit and Force Quit have different consequences

Use the app’s own Quit command when it responds. In Activity Monitor, select a process and click **Stop** to see the quitting options. **Quit** allows it to close when safe; **Force Quit** ends it immediately and can lose unsaved work or affect other processes that depend on it. Use Force Quit for an identified app that will not close normally. [Apple’s quitting instructions](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1002/10.14/mac/15.0)

If the busy process is **kernel_task**, take a different approach. Apple explains that one of its roles is temperature management: it can limit CPU availability to intensive processes in response to heat-related conditions. Treat it as a clue about those conditions, rather than an app to force quit. [Apple’s kernel_task explanation](https://support.apple.com/en-ie/102172)

## Read Memory Pressure before Memory Used

Select **Memory** and look at the **Memory Pressure** graph. Apple describes green as efficient memory use, yellow as a possible need for more RAM, and red as a need for more RAM. Unused memory does not necessarily improve performance. [Apple’s memory-pressure guidance](https://support.apple.com/en-asia/guide/activity-monitor/actmntr34865/10.14/mac/15.0)

If pressure is yellow, red or spiking during the slowdown, sort by **Memory**. Find an app you no longer need, save its work and quit it. Then check whether both pressure and responsiveness improve. Apple recommends investigating app use when pressure rises. Look for a recurring pattern in your usual workload before considering a hardware purchase. [Apple’s memory-pressure guidance](https://support.apple.com/en-asia/guide/activity-monitor/actmntr34865/10.14/mac/15.0)

The other memory figures need context:

- **Cached Files:** memory used to keep files handy so they can be reopened faster.
- **Compressed:** memory macOS has compressed to make room for active apps.
- **Swap Used:** startup-disk space used to move data to and from RAM.

Apple’s pressure calculation considers several factors, including swap rate. Our inference: a nonzero swap amount alone cannot establish the cause of a pause. Read it alongside pressure and what you experience. [Apple’s memory definitions](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac)

## Check available storage before deleting files

Open **System Settings → General → Storage**. Apple identifies insufficient startup-disk space as another possible cause of slow performance. If available space is low, inspect what occupies it before choosing anything to remove. [Apple’s slowdown checklist](https://support.apple.com/en-mide/guide/mac-help/mchlp1731/27/mac/27)

Our [guide to finding what’s taking up space on a Mac](https://venkateshdas.github.io/pulse/guides/whats-taking-up-space-on-mac/) walks through storage categories, large-file searches and folder totals. Review files you recognise and no longer need. Avoid treating an unfamiliar system folder as a cleanup target just because it is large.

## Choose the next step from what you observed

This table applies the checks above. It is a troubleshooting aid, not a set of diagnostic thresholds.

| What you observe during the slowdown | What to try next |
| --- | --- |
| A recognised, unneeded app stays busy on CPU | Save and quit that app, then repeat the slow task. |
| Memory Pressure rises and an unneeded app uses substantial memory | Save and quit that app; compare pressure and responsiveness. |
| Available storage is low | Follow the storage guide to inspect files before removing anything. |
| Only one app repeatedly stalls without a clear CPU or memory pattern | Check its compatibility requirements; take your notes to its developer. |
| The whole Mac keeps stalling without a clear pattern | Take the observations to Apple Support rather than terminating unfamiliar processes. |

For example, **a hypothetical result** might be: “Switching to my document stalled while memory pressure was yellow. After saving and quitting an unused app, pressure returned to green and switching felt responsive.” That supports investigating the workload’s memory demand. It does not prove the app has a defect or that the Mac needs replacing.

Keep the task, reading, change and result in your notes. Green memory pressure or low CPU activity does not rule out other software or hardware problems. If the slowdown returns, those notes give the app developer or Apple Support something more specific to investigate.

## Observe the same signals in Pulse

Pulse’s native dashboard includes CPU and memory readings, memory-pressure indicators and swap information. Those readings support observation; they do not guarantee a diagnosis or speedup. You can complete this guide using Activity Monitor without installing Pulse.

[Explore Pulse or join the early-access waitlist](https://venkateshdas.github.io/pulse/).
