import "$styles/index.css"

import { setupTheme } from "./site/theme.js"
import { setupTabs, setupInstall } from "./site/tabs.js"
import { setupProgress } from "./site/progress.js"
import { setupCopGrid } from "./site/cop_grid.js"
import { setupCopIndex } from "./site/cop_index.js"

setupTheme()
setupTabs()
setupInstall()
setupProgress()
setupCopGrid()
setupCopIndex()
