import os
import time
import sys
import traceback
import json
from appium import webdriver
from selenium.common.exceptions import WebDriverException, NoSuchElementException


def main():
    user = os.environ.get("BROWSERSTACK_USERNAME")
    key = os.environ.get("BROWSERSTACK_ACCESS_KEY")
    app_url = os.environ.get("APP_URL")
    device = os.environ.get("DEVICE_NAME", "iPhone 15")
    os_version = os.environ.get("OS_VERSION", "17")
    if not (user and key and app_url):
        print("Missing BROWSERSTACK credentials or APP_URL", file=sys.stderr)
        sys.exit(1)

    # Use W3C capabilities with BrowserStack bstack:options
    caps = {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:app": app_url,
        "appium:autoAcceptAlerts": True,
        "appium:newCommandTimeout": 120,
        "bstack:options": {
            "deviceName": device,
            "osVersion": os_version,
            "projectName": "CodeSnake",
            "buildName": f"BS Smoke {int(time.time())}",
            "sessionName": "Launch + Run button tap",
            "debug": True,
            "deviceLogs": True,
            "networkLogs": True,
            "appiumLogs": True,
        },
    }

    remote = f"https://{user}:{key}@hub-cloud.browserstack.com/wd/hub"
    driver = None
    crashed = False
    session_url = None
    try:
        driver = webdriver.Remote(remote, caps)
        # Fetch public session URL via executor API for reliability
        try:
            details = driver.execute_script('browserstack_executor: {"action": "getSessionDetails"}')
            if isinstance(details, dict) and details.get("public_url"):
                session_url = details["public_url"]
        except Exception:
            pass
        if not session_url:
            session_id = driver.session_id
            session_url = f"https://app-automate.browserstack.com/dashboard/v2/sessions/{session_id}"
        with open("bs_session.txt", "w") as f:
            f.write(session_url)
        print(f"BrowserStack session: {session_url}")

        # Wait for app to settle
        time.sleep(5)

        # Try to find and tap a button labeled "Run"
        tapped = False
        try:
            run_btn = driver.find_element("-ios predicate string", "type == 'XCUIElementTypeButton' AND (name CONTAINS 'Run' OR label CONTAINS 'Run')")
            run_btn.click()
            tapped = True
            print("Tapped Run button by label")
        except NoSuchElementException:
            # Fallback: try any visible 'Run' static text then its parent
            try:
                static = driver.find_element("-ios predicate string", "type == 'XCUIElementTypeStaticText' AND (name CONTAINS 'Run' OR label CONTAINS 'Run')")
                static.click()
                tapped = True
                print("Tapped Run static text fallback")
            except Exception:
                print("Run control not found; continuing to observe for crashes")

        # Observe for crash for up to 20 seconds
        for i in range(20):
            try:
                _ = driver.page_source  # will raise if session died
            except WebDriverException:
                crashed = True
                print("Session appears to have crashed (driver/page_source failed)")
                break
            time.sleep(1)

        # Mark session status for BrowserStack dashboard
        status = "passed" if not crashed else "failed"
        reason = "No crash detected" if not crashed else "App crashed during smoke test"
        try:
            driver.execute_script('browserstack_executor: {"action": "setSessionStatus", "arguments": {"status":"%s", "reason": "%s"}}' % (status, reason))
        except Exception:
            pass

        if crashed:
            sys.exit(1)
    except Exception as e:
        crashed = True
        traceback.print_exc()
        sys.exit(1)
    finally:
        try:
            if driver is not None:
                driver.quit()
        except Exception:
            pass


if __name__ == "__main__":
    main()
