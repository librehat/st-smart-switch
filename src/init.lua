-- Copyright 2024 @librehat (Simeon Huang)
-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"
local log = require "log"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement

-- Quirks table (if needed)
local SWITCH_POWER_CONFIGS = {
  { mfr = "innr", model = "SP 242", energy = { divisor = 1 }, power = { divisor = 1 } },
}

local function get_config(device)
  for _, fingerprint in ipairs(SWITCH_POWER_CONFIGS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return fingerprint
    end
  end
end

------------------Zigbee handlers------------------------

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) or 1
  log.trace("Power meter report received raw value=", raw_value, "divisor=", divisor)

  raw_value = raw_value / divisor
  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function energy_meter_power_consumption_report(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1
  log.trace("Energy meter report received raw value=", raw_value, "divisor=", divisor)

  raw_value = raw_value / divisor
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))
end

------------------Driver lifecycles------------------------
local function do_configure(driver, device)
  device:refresh()
  device:configure()

  -- One-time read from the device
  device:send(SimpleMetering.attributes.Divisor:read(device))
  device:send(SimpleMetering.attributes.Multiplier:read(device))
  device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
  device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
end

local function device_init(driver, device)
  local config = get_config(device)
  if config ~= nil then
    device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, config.power.divisor, { persist = true })
    device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, config.energy.divisor, { persist = true })
  end
end

--------------Driver Main-------------------

local zigbee_switch_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.energyMeter,
    capabilities.powerMeter,
  },
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_power_consumption_report
      },
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
  },
}
defaults.register_for_default_handlers(zigbee_switch_driver, zigbee_switch_driver.supported_capabilities)

local zigbee_driver = ZigbeeDriver("zigbee-smart-switch", zigbee_switch_driver)
zigbee_driver:run()
