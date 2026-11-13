// The page scroll bar is hidden while the page sits at its top and shown from
// the first scroll on: the rule in the margin belongs to the text, and there
// is no text to rule above the fold. The channel keeps its width, so nothing
// shifts when the thumb arrives.
const root = document.documentElement;
const mark = () => root.classList.toggle("at-top", scrollY === 0);
addEventListener("scroll", mark, { passive: true });
mark();
