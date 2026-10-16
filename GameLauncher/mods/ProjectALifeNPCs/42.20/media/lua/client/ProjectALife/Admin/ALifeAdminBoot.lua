require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminClientActions"
require "ProjectALife/Admin/ALifeAdminWindow"
require "ProjectALife/Admin/ALifeSpawnerBrowser"
require "ProjectALife/Admin/ALifeSpawnerPanel"
require "ProjectALife/Admin/ALifeAdminTabPopulation"
require "ProjectALife/Admin/ALifeAdminTabWorld"
require "ProjectALife/Admin/ALifeAdminTabReputation"
require "ProjectALife/Admin/ALifeAdminTabDiagnostics"
require "ProjectALife/Admin/ALifeAdminTabSettings"
require "ProjectALife/Admin/ALifeAdminTabCleanup"

ProjectALife = ProjectALife or {}

ProjectALife.AdminConsole.installed = true

return ProjectALife.AdminConsole
