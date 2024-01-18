"use strict";
// ==UserScript==
// @name         Bitbucket
// @namespace    Ascendcorp
// @version      1.0.0
// @description  automation script for Ascendcorp Bitbucket
// @author       Lumi
// @match        https://bitbucket.org/ascendcorp/*/pull-requests/new
// @icon         https://www.google.com/s2/favicons?sz=64&domain=bitbucket.org
// @downloadURL  https://github.com/ascendcorp/userscripts/dist/bitbucket.user.js
// @updateURL    https://github.com/ascendcorp/userscripts/dist/bitbucket.user.js
// @grant        none
// ==/UserScript==
// ─── Configurations ──────────────────────────────────────────────────────────
const deleteBranchAfterMerge = true;
// ─── Utilities ───────────────────────────────────────────────────────────────
const log = (message) => console.log(`🤖 ${message}`);
const waitForElement = async (selector) => {
    return new Promise((resolve) => {
        const targetNode = document.querySelector(selector);
        if (targetNode) {
            resolve(targetNode);
            return;
        }
        const isElement = (item) => {
            return item instanceof Element;
        };
        const observer = new MutationObserver((mutationsList, observer) => {
            for (let mutation of mutationsList) {
                const isMatched = Array.from(mutation.addedNodes).some((node) => {
                    if (!isElement(node)) {
                        return false;
                    }
                    return node.matches && node.matches(selector);
                });
                if (mutation.type === 'childList' && isMatched) {
                    observer.disconnect();
                    const target = document.querySelector(selector);
                    resolve(target);
                    break;
                }
            }
        });
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
        });
    });
};
// ─── Selectors ───────────────────────────────────────────────────────────────
const sourceBranchSection = 'div[data-testid="create-pull-request-source-branch-selector"]';
const deleteBranchCheckboxSelector = 'input[type="checkbox"][name="deleteSourceBranch"]';
(() => {
    'use strict';
    const getBranchName = async () => {
        const section = await waitForElement(sourceBranchSection);
        // NOTE: risky to change by Bitbucket
        const branchElement = section?.lastElementChild?.firstElementChild?.children[2].firstElementChild?.firstElementChild?.firstElementChild
            ?.lastElementChild;
        const branchName = branchElement?.innerHTML;
        return branchName ?? '';
    };
    const markDeleteBranchAfterMerge = async () => {
        const deleteBranchCheckbox = await waitForElement(deleteBranchCheckboxSelector);
        const isChecked = deleteBranchCheckbox?.checked;
        if (!isChecked && deleteBranchCheckbox) {
            log('checked delete the branch after merged');
            deleteBranchCheckbox.click();
        }
    };
    let sourceBranch = '';
    window.addEventListener('load', async () => {
        // NOTE: polling for branch changing because Bitbucket not reload the page after changed branch
        setInterval(async () => {
            let branchName = await getBranchName();
            if (branchName !== sourceBranch) {
                sourceBranch = branchName;
                log(`current branch is ${branchName}`);
            }
            await markDeleteBranchAfterMerge();
        }, 1000);
    });
})();
