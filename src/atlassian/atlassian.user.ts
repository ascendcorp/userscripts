// ==UserScript==
// @name         Atlassian
// @namespace    Ascendcorp
// @version      1.0.0
// @description  automation script for Ascendcorp Atlassian
// @author       Lumi
// @match        https://truemoney.atlassian.net/*
// @icon         https://www.google.com/s2/favicons?sz=64&domain=atlassian.net
// @downloadURL  https://raw.githubusercontent.com/Ascendcorp/userscripts/main/dist/atlassian/atlassian.user.js
// @updateURL    https://raw.githubusercontent.com/Ascendcorp/userscripts/main/dist/atlassian/atlassian.user.js
// @grant        GM_setClipboard
// ==/UserScript==

// ─── Selectors ───────────────────────────────────────────────────────────────

const idSection = 'div[data-testid="issue.views.issue-base.foundation.breadcrumbs.breadcrumb-current-issue-container"]'
const nameSection = 'h1[data-testid="issue.views.issue-base.foundation.summary.heading"]'
const toolbarSection = 'span[data-testid="issue-view-foundation.quick-add.link-button.wrapper"]'

;(() => {
  'use strict'

  // ─── Utilities ───────────────────────────────────────────────────────────────

  const log = (message: unknown) => console.log(`🤖 ${message}`)

  const waitForElement = async <T extends Element>(selector: string): Promise<T | null> => {
    return new Promise((resolve) => {
      const targetNode = document.querySelector<T>(selector)

      if (targetNode) {
        resolve(targetNode)
        return
      }

      const isElement = (item: Element | Node): item is Element => {
        return item instanceof Element
      }

      const observer = new MutationObserver((mutationsList, observer) => {
        for (let mutation of mutationsList) {
          const isMatched = Array.from(mutation.addedNodes).some((node) => {
            if (!isElement(node)) {
              return false
            }
            return node.matches && node.matches(selector)
          })

          if (mutation.type === 'childList' && isMatched) {
            observer.disconnect()
            const target = document.querySelector<T>(selector)
            resolve(target)
            break
          }
        }
      })

      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
      })
    })
  }

  // ─── Core ────────────────────────────────────────────────────────────────────

  const getTicketCode = async () => {
    const section = await waitForElement(idSection)
    // NOTE: risky to change by Atlassian
    const type = (
      section?.firstElementChild?.firstElementChild?.firstElementChild?.firstElementChild?.firstElementChild?.getAttribute(
        'alt',
      ) ?? ''
    ).toLowerCase()

    const id = section?.children[1]?.firstElementChild?.firstElementChild?.firstElementChild?.innerHTML ?? ''

    return { type, id }
  }

  const getTicketName = async () => {
    const section = await waitForElement(nameSection)
    // NOTE: risky to change by Atlassian
    const name = section?.innerHTML ?? ''

    return name
  }

  const injectToolbar = async (branchName: string) => {
    const buttonId = 'copy-branch-name-btn'

    if (document.getElementById(buttonId)) {
      return
    }

    const onCopy = () => {
      GM_setClipboard(branchName)
    }

    const controllerElement = `
    <button id="${buttonId}" style="margin-left: 8px;">Copy Git Branch</button>
`
    const section = await waitForElement(toolbarSection)
    section?.parentElement?.insertAdjacentHTML('beforeend', controllerElement)

    const copyButton = await waitForElement(`button[id="${buttonId}"]`)
    copyButton?.addEventListener('click', onCopy)
  }

  const generateBranchName = (type: string, id: string, name: string) => {
    const prefix = type === 'bug' ? 'fix' : 'feature'
    const symbolRegex = /[^\w\s]/gi
    const title = name
      .replace(/(\[.*?\])/g, '') // NOTE: replace bracket contents
      .replace(symbolRegex, ' ')
      .trim()
      .split(' ')
      .filter((word) => word)
      .map((word) => word.toLowerCase())
      .join('-')

    return `${prefix}/${id}-${title}`
  }

  window.addEventListener('load', async () => {
    // NOTE: polling for ticket changing because Atlassian not reload the page after changed branch
    setInterval(async () => {
      const { type, id } = await getTicketCode()
      const name = await getTicketName()
      const branchName = generateBranchName(type, id, name)
      log(branchName)
      await injectToolbar(branchName)
    }, 1000)
  })
})()
