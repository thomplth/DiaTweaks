# Discard inactive tabs

Dia keeps a tab's page in memory long after you've stopped using it. This tweak discards any tab you haven't looked at for
a set time, which frees its memory and usually lets its renderer process exit. Click the tab and the page loads again.

Pick the time in **Settings → Patches → Discard Inactive Tabs**: 15 minutes to 1 day, 2 hours by default.

It leaves a tab alone while it:

- is on screen, including the current tab of a window in the background
- is playing audio, in Picture in Picture or sharing its screen
- is loading, or you've typed in a form on the page since it loaded
- is a site on Dia's keep-alive list, such as Slack, Gmail, Notion, Linear, Figma and Google Docs

## How tabs look

| Tab | Look |
| --- | --- |
| Discarded, or not loaded since Dia opened | Dotted ring around the favicon, dimmed |
| Closed pinned tab, in the top row or the pinned list | Dimmed, no ring |

A discarded tab loses what only lived in the page, such as its scroll position on some sites.

The time restarts when Dia opens, and when a tab stops playing audio, leaves Picture in Picture or stops sharing its screen.
Time your Mac spends asleep counts, so tabs you left overnight are discarded soon after it wakes.

Turn it on in **Settings → Patches**, or with `diatweaks enable discardInactiveTabs`.
