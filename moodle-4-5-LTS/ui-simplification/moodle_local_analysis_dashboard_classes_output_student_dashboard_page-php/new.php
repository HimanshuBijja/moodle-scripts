<?php
// This file is part of Moodle - http://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <http://www.gnu.org/licenses/>.

namespace local_analysis_dashboard\output;

use renderable;
use templatable;
use renderer_base;
use stdClass;
use local_analysis_dashboard\local\widget_registry;

/**
 * Student dashboard page renderable.
 *
 * Prepares user-level widget configuration data for the Mustache template.
 *
 * @package    local_analysis_dashboard
 * @copyright  2026 Analysis Dashboard
 * @license    http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class student_dashboard_page implements renderable, templatable {

    /** @var int The user ID. */
    private int $userid;

    /**
     * Constructor.
     *
     * @param int $userid The user ID.
     */
    public function __construct(int $userid) {
        $this->userid = $userid;
    }

    /**
     * Export data for the template.
     *
     * @param renderer_base $output The renderer.
     * @return stdClass Template data.
     */
    public function export_for_template(renderer_base $output): stdClass {
        global $DB, $USER;

        $data = new stdClass();
        $user = $DB->get_record('user', ['id' => $this->userid], 'id, firstname, lastname, email', MUST_EXIST);

        // Get widgets that support user context.
        $allwidgets = widget_registry::get_all();
        $data->widgets = [];

        foreach ($allwidgets as $id => $widget) {
            // Only include widgets that support CONTEXT_USER.
            if (!in_array(CONTEXT_USER, $widget->get_supported_context_levels())) {
                continue;
            }
            $data->widgets[] = (object) [
                'id' => $id,
                'name' => get_string($widget->get_name(), 'local_analysis_dashboard'),
                'type' => $widget->get_type(),
            ];
        }

        $data->has_widgets = !empty($data->widgets);
        $data->widgets_json = json_encode($data->widgets);
        $data->userid = $this->userid;
        $data->username = fullname($user);
        // $data->pagetitle = get_string('student_dashboard', 'local_analysis_dashboard');
        $data->pagesubtitle = get_string('student_dashboard_subtitle', 'local_analysis_dashboard', fullname($user));
        $data->no_widgets_message = get_string('no_widgets_available', 'local_analysis_dashboard');

        return $data;
    }
}
