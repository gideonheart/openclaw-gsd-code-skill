Claude is asking a question. Review the [ASK USER QUESTION] section above and respond.

Single-select (numbered options):
  {MENU_DRIVER_PATH} {SESSION_NAME} choose <n>            Select option by number

Multi-select (checkboxes — when "Multi-select: yes"):
  {MENU_DRIVER_PATH} {SESSION_NAME} arrow_down            Move cursor down to next option
  {MENU_DRIVER_PATH} {SESSION_NAME} arrow_up              Move cursor up to previous option
  {MENU_DRIVER_PATH} {SESSION_NAME} space                 Toggle checkbox on/off for current option
  {MENU_DRIVER_PATH} {SESSION_NAME} enter                 Confirm selection and submit
  Typical flow: arrow_down to navigate, space to toggle each desired option, enter to confirm.

Freeform text (open-ended questions):
  {MENU_DRIVER_PATH} {SESSION_NAME} type <text>           Type a freeform answer and submit

Inspect current state:
  {MENU_DRIVER_PATH} {SESSION_NAME} snapshot              Take a pane snapshot to see the TUI state