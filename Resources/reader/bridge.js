// Bridge between the SwiftUI reader chrome and foliate-js.
//
// foliate-js is the same engine Grimmory's web reader runs, which is the whole
// point: the CFIs reported by `relocate` here are the same ones the server
// stores, so a position written from the phone resolves exactly in the browser,
// on a Kobo, or in KOReader.

import './foliate/view.js'

const post = (type, payload = {}) => {
    window.webkit?.messageHandlers?.reader?.postMessage({ type, ...payload })
}

const SWIPE_DOWN_MIN_PX = 56
const SWIPE_DOWN_AXIS_RATIO = 1.2
// Comfortable tap jitter tolerance on high-DPI touch screens.
const TAP_MAX_MOVE_PX = 24

const showError = message => {
    const el = document.getElementById('error')
    el.style.display = 'block'
    el.textContent = message
    post('error', { message })
}

const contentCSS = ({ lineHeight, justify, hyphenate, fontSize, fontFamily, theme }) => `
    @namespace epub "http://www.idpf.org/2007/ops";
    html {
        color-scheme: ${theme === 'dark' ? 'dark' : 'light'};
        ${theme === 'sepia' ? 'background: #f4ecd8 !important; color: #5b4636 !important;' : ''}
        ${theme === 'dark' ? 'background: #101014 !important; color: #d8d8dc !important;' : ''}
        font-size: ${fontSize}%;
        ${fontFamily ? `font-family: ${fontFamily} !important;` : ''}
    }
    ${theme === 'sepia' ? 'body, p, div, span, li { color: #5b4636 !important; }' : ''}
    ${theme === 'dark' ? 'body, p, div, span, li { color: #d8d8dc !important; }' : ''}
    p, li, blockquote, dd {
        line-height: ${lineHeight};
        text-align: ${justify ? 'justify' : 'start'};
        -webkit-hyphens: ${hyphenate ? 'auto' : 'manual'};
        hyphens: ${hyphenate ? 'auto' : 'manual'};
        widows: 2;
    }
    [align="left"] { text-align: left; }
    [align="right"] { text-align: right; }
    [align="center"] { text-align: center; }
    pre { white-space: pre-wrap !important; }
    a:any-link { color: ${theme === 'dark' ? '#7fb2ff' : '#0a63c9'}; }
`

class Reader {
    #view = null
    #style = {
        lineHeight: 1.5,
        justify: true,
        hyphenate: true,
        fontSize: 100,
        fontFamily: null,
        theme: 'light',
        flow: 'paginated',
        margin: 6,
    }

    get style() { return this.#style }

    async open({ url, lastLocation, style }) {
        try {
            Object.assign(this.#style, style ?? {})

            const response = await fetch(url)
            if (!response.ok) throw new Error(`Couldn't read the book file (${response.status})`)
            const blob = await response.blob()
            // foliate-js identifies the format from the bytes, but a name helps
            // it distinguish EPUB from CBZ, both of which are zips.
            const file = new File([blob], 'book.epub', { type: 'application/epub+zip' })

            const view = document.createElement('foliate-view')
            document.body.append(view)
            this.#view = view

            await view.open(file)
            view.addEventListener('relocate', e => this.#onRelocate(e.detail))
            view.addEventListener('load', e => this.#onLoad(e.detail))

            this.#applyFlow()
            this.#applyStyle()

            await view.init({ lastLocation: lastLocation || null })

            post('ready', {
                toc: flattenTOC(view.book?.toc ?? []),
                title: view.book?.metadata?.title ?? null,
                // Report where we actually landed, so Swift can tell whether
                // the stored CFI resolved or the book opened at the start.
                resolved: Boolean(lastLocation),
            })
        } catch (error) {
            showError(error?.message ?? String(error))
        }
    }

    #onRelocate(detail) {
        post('relocate', {
            cfi: detail?.cfi ?? null,
            // The spine href is stored alongside the CFI as positionHref.
            href: this.#view?.book?.sections?.[detail?.section?.current]?.id ?? null,
            fraction: detail?.fraction ?? null,
            tocLabel: detail?.tocItem?.label ?? null,
            sectionCurrent: detail?.section?.current ?? null,
            sectionTotal: detail?.section?.total ?? null,
        })
    }

    #onLoad({ doc }) {
        // Forward taps so SwiftUI can toggle its chrome: the content lives in
        // an iframe, so gestures never reach the host view on their own.
        if (!doc || doc.documentElement?.dataset?.scriptoriumGesturesBound === '1') return
        doc.documentElement.dataset.scriptoriumGesturesBound = '1'

        let touchStart = null
        let suppressNextClick = false
        const claimTapGesture = event => {
            event.preventDefault()
            event.stopPropagation()
            event.stopImmediatePropagation?.()
        }
        doc.addEventListener('touchstart', event => {
            if (event.touches?.length !== 1) { touchStart = null; return }
            const touch = event.touches[0]
            touchStart = { x: touch.clientX, y: touch.clientY }
        }, { passive: true })
        // foliate's own paginator binds touchmove/touchend on this same
        // document to drive its drag-to-turn-page gesture. Left alone, an
        // ordinary tap's inevitable pixel or two of jitter still reaches it:
        // it nudges the page via scrollBy() and marks its drag state dirty,
        // and since we claim touchend below (blocking its matching cleanup/
        // snap), that dirty state never gets a chance to resettle before the
        // next gesture. So while a touch is still within tap tolerance, keep
        // foliate from seeing it at all; only once it's clearly a real drag
        // do we step back and let foliate's native handling take over.
        doc.addEventListener('touchmove', event => {
            if (!touchStart || event.touches?.length !== 1) return
            const touch = event.touches[0]
            const moved = Math.max(
                Math.abs(touch.clientX - touchStart.x),
                Math.abs(touch.clientY - touchStart.y)
            )
            if (moved <= TAP_MAX_MOVE_PX) claimTapGesture(event)
        }, { passive: false, capture: true })
        doc.addEventListener('touchend', event => {
            if (!touchStart || event.changedTouches?.length !== 1) {
                touchStart = null
                return
            }
            const touch = event.changedTouches[0]
            const dx = touch.clientX - touchStart.x
            const dy = touch.clientY - touchStart.y
            touchStart = null
            const moved = Math.max(Math.abs(dx), Math.abs(dy))

            const width = doc.defaultView?.innerWidth ?? 0
            const x = touch.clientX
            const inLeftZone = this.#style.flow === 'paginated' && width && x <= width * 0.25
            const inRightZone = this.#style.flow === 'paginated' && width && x >= width * 0.75

            // Handle taps from touch directly to avoid fighting synthetic clicks.
            if (moved <= TAP_MAX_MOVE_PX) {
                suppressNextClick = true
                claimTapGesture(event)
                if (inLeftZone) return this.prev()
                if (inRightZone) return this.next()
                return post('tap')
            }

            // Pulling down should bring UI chrome back while in fullscreen.
            if (dy > SWIPE_DOWN_MIN_PX && dy > Math.abs(dx) * SWIPE_DOWN_AXIS_RATIO) {
                suppressNextClick = true
                post('showChrome')
            }
        }, { passive: false, capture: true })
        doc.addEventListener('touchcancel', () => {
            touchStart = null
        }, { passive: true })
        doc.addEventListener('click', event => {
            // The synthetic click that follows a handled touch is suppressed
            // by preventDefault() above, but this is a defense-in-depth
            // backstop rather than a timing guess: it clears on the very
            // next click, whenever that arrives.
            if (suppressNextClick) {
                suppressNextClick = false
                return
            }
            const width = doc.defaultView?.innerWidth ?? 0
            const x = event.clientX
            if (this.#style.flow === 'paginated' && width) {
                if (x <= width * 0.25) {
                    event.preventDefault()
                    event.stopPropagation()
                    this.prev()
                    return
                }
                if (x >= width * 0.75) {
                    event.preventDefault()
                    event.stopPropagation()
                    this.next()
                    return
                }
            }
            post('tap')
        })
    }

    #applyFlow() {
        this.#view?.renderer?.setAttribute('flow', this.#style.flow)
        this.#view?.renderer?.setAttribute('gap', `${this.#style.margin}%`)
        document.documentElement.style.setProperty(
            '--page-bg',
            this.#style.theme === 'dark' ? '#101014'
                : this.#style.theme === 'sepia' ? '#f4ecd8' : '#ffffff',
        )
    }

    #applyStyle() {
        this.#view?.renderer?.setStyles?.(contentCSS(this.#style))
    }

    setStyle(style) {
        const flowChanged = style.flow && style.flow !== this.#style.flow
        Object.assign(this.#style, style)
        this.#applyFlow()
        this.#applyStyle()
        if (flowChanged) this.#view?.renderer?.goTo?.({ index: 0, anchor: 0 })
    }

    goTo(target) { return this.#view?.goTo(target) }
    goToFraction(fraction) { return this.#view?.goToFraction(fraction) }
    next() { return this.#view?.next() }
    prev() { return this.#view?.prev() }
}

const flattenTOC = (items, depth = 0, out = []) => {
    for (const item of items) {
        out.push({ label: item.label ?? '', href: item.href ?? '', depth })
        if (item.subitems?.length) flattenTOC(item.subitems, depth + 1, out)
    }
    return out
}

window.reader = new Reader()
post('bridgeReady')
