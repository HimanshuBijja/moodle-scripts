<?php
/**
 * Analysis Dashboard — Data Population Script
 *
 * Creates 25 users with Telangana (Indian) names, 5 courses with quizzes,
 * assignments, forums, and pages, then populates all data that the
 * local_analysis_dashboard plugin widgets query:
 *
 *   - Users, courses, categories, enrolments
 *   - Course completions & activity completions
 *   - Grade items & grade_grades
 *   - Quiz & quiz_attempts
 *   - logstore_standard_log (course views, logins, activity events)
 *
 * Run inside the Moodle container:
 *   php /var/www/html/populate_dashboard_data.php [--password-suffix=SUFFIX]
 */

define('CLI_SCRIPT', true);
require(__DIR__ . '/config.php');

global $DB, $CFG, $USER;

// Prevent email errors.
$CFG->noreplyaddress = 'noreply@example.com';
$CFG->noemailever = true;

require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/lib/enrollib.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/course/modlib.php');
require_once($CFG->libdir  . '/clilib.php');
require_once($CFG->libdir  . '/gradelib.php');
require_once($CFG->libdir  . '/filelib.php');

// Run as admin.
$USER = get_admin();

// Parse CLI options.
[$options, $unrecognised] = cli_get_params(
    ['password-suffix' => '123456', 'help' => false],
    ['p' => 'password-suffix', 'h' => 'help']
);
if ($options['help']) {
    echo "Usage: php populate_dashboard_data.php [--password-suffix=SUFFIX]\n";
    echo "  --password-suffix, -p   Password suffix for all accounts (default: 123456)\n";
    exit(0);
}
$passwordSuffix = $options['password-suffix'];

// ──────────────────────────────────────────────
// CONFIGURATION
// ──────────────────────────────────────────────

$NUM_USERS = 25;

// Telangana Indian first names.
$FIRST_NAMES = [
    'Ravi', 'Srinivas', 'Venkatesh', 'Harish', 'Naresh',
    'Kavita', 'Swathi', 'Jyothi', 'Sravani', 'Lavanya',
    'Sai', 'Krishna', 'Arjun', 'Bhanu', 'Ganesh',
    'Lakshmi', 'Manasa', 'Pradeep', 'Rajesh', 'Shiva',
    'Divya', 'Kiran', 'Anil', 'Charitha', 'Sandeep',
];

// Telangana last names.
$LAST_NAMES = [
    'Reddy', 'Rao', 'Goud', 'Sharma', 'Chary',
    'Varma', 'Raju', 'Gupta', 'Naidu', 'Kumar',
    'Chowdary', 'Yadav', 'Mudiraj', 'Kamma', 'Kapu',
    'Velama', 'Patel', 'Singireddy', 'Thota', 'Mekala',
    'Gujjula', 'Marri', 'Vangala', 'Pittala', 'Komaravelli',
];

$COURSE_DEFS = [
    [
        'fullname'  => 'Cyber Security Fundamentals',
        'shortname' => 'CYBER101',
        'summary'   => 'Learn the basics of cyber security, network defence, and threat analysis.',
        'category'  => 'Technology',
        'forums'    => ['Security Discussion', 'Tool Reviews'],
        'assigns'   => ['Threat Assessment Report', 'Network Audit'],
        'pages'     => ['Security Resources'],
        'quizzes'   => ['Basics Quiz', 'Advanced Quiz'],
    ],
    [
        'fullname'  => 'Data Science with Python',
        'shortname' => 'DSCI201',
        'summary'   => 'Master data analysis, visualisation and machine learning with Python.',
        'category'  => 'Technology',
        'forums'    => ['Python Tips', 'ML Discussion'],
        'assigns'   => ['EDA Project', 'ML Model Submission'],
        'pages'     => ['Python Cheat Sheet', 'Dataset Sources'],
        'quizzes'   => ['Python Basics', 'Statistics Quiz'],
    ],
    [
        'fullname'  => 'Business Analytics',
        'shortname' => 'BA301',
        'summary'   => 'Apply analytics to solve business problems using data-driven approaches.',
        'category'  => 'Business',
        'forums'    => ['Case Study Discussion'],
        'assigns'   => ['Dashboard Design', 'KPI Analysis Report', 'Final Presentation'],
        'pages'     => ['Analytics Tools'],
        'quizzes'   => ['Analytics Concepts'],
    ],
    [
        'fullname'  => 'Cloud Computing Essentials',
        'shortname' => 'CLOUD401',
        'summary'   => 'Understand cloud architectures, deployment models, and services.',
        'category'  => 'Technology',
        'forums'    => ['Cloud Providers Comparison', 'Certification Prep'],
        'assigns'   => ['Cloud Architecture Design'],
        'pages'     => ['AWS vs Azure Guide'],
        'quizzes'   => ['Cloud Basics', 'Services Quiz', 'Security Quiz'],
    ],
    [
        'fullname'  => 'Effective Leadership',
        'shortname' => 'LEAD501',
        'summary'   => 'Build leadership skills for managing teams and driving organisational change.',
        'category'  => 'Management',
        'forums'    => ['Leadership Styles', 'Team Management Tips'],
        'assigns'   => ['Leadership Case Study', 'Team Building Plan'],
        'pages'     => ['Leadership Books'],
        'quizzes'   => ['Leadership Concepts'],
    ],
];

$DISCUSSION_SUBJECTS = [
    'Has anyone tried a different approach?',
    'Great resource to share',
    'Need help understanding this concept',
    'Tips for this week\'s material',
    'My experience with the assignment',
    'Question about expectations',
    'Interesting related article',
    'Study group — who\'s in?',
    'Feedback on my draft',
    'Any advice on this topic?',
];

$DISCUSSION_MESSAGES = [
    '<p>I have been working through the material and wanted to share some thoughts. Practice makes a huge difference.</p>',
    '<p>Breaking the problem into smaller parts really helps. Has anyone else tried this?</p>',
    '<p>I found an interesting example that relates to our course. It helped me understand practical applications.</p>',
    '<p>This week\'s content is quite challenging. Any additional resources to recommend?</p>',
    '<p>Great lecture! I especially liked the hands-on component.</p>',
];

$REPLY_MESSAGES = [
    '<p>I completely agree. Consistent practice is key.</p>',
    '<p>Thanks for sharing! I will try this approach.</p>',
    '<p>Good perspective. Reviewing fundamentals regularly helps a lot.</p>',
    '<p>Could you elaborate? I am curious about the specific steps.</p>',
    '<p>Great insight! Bookmarked for future reference.</p>',
];

$SUBMISSION_TEXTS = [
    '<p>After thorough research and analysis, I have completed this assignment addressing all key requirements.</p>',
    '<p>This submission presents my work. I reviewed relevant literature and developed my solution step by step.</p>',
    '<p>I took an iterative approach, starting with an outline and refining progressively.</p>',
    '<p>Please find my completed work. I referenced multiple sources and cross-validated my approach.</p>',
];

// ──────────────────────────────────────────────
// HELPER FUNCTIONS
// ──────────────────────────────────────────────

function dashboard_add_cm($courseid, $modulename, $instanceid, $sectionnum) {
    global $DB;
    $module = $DB->get_record('modules', ['name' => $modulename], '*', MUST_EXIST);
    $cm = new stdClass();
    $cm->course           = $courseid;
    $cm->module           = $module->id;
    $cm->instance         = $instanceid;
    $cm->visible          = 1;
    $cm->visibleoncoursepage = 1;
    $cm->completion       = 1;
    $cm->added            = time();
    $cmid = $DB->insert_record('course_modules', $cm);

    $course = $DB->get_record('course', ['id' => $courseid]);
    course_add_cm_to_section($course, $cmid, $sectionnum);
    return $cmid;
}

function dashboard_add_forum($courseid, $name, $sectionnum) {
    global $DB;
    $forum = new stdClass();
    $forum->course       = $courseid;
    $forum->type         = 'general';
    $forum->name         = $name;
    $forum->intro        = '<p>Welcome to the ' . $name . ' forum.</p>';
    $forum->introformat  = FORMAT_HTML;
    $forum->timemodified = time();
    $forum->id = $DB->insert_record('forum', $forum);
    $forum->cmid = dashboard_add_cm($courseid, 'forum', $forum->id, $sectionnum);
    return $forum;
}

function dashboard_add_assignment($courseid, $name, $startdate, $enddate, $sectionnum) {
    global $DB;
    $assign = new stdClass();
    $assign->course                      = $courseid;
    $assign->name                        = $name;
    $assign->intro                       = '<p>Complete and submit: ' . $name . '</p>';
    $assign->introformat                 = FORMAT_HTML;
    $assign->alwaysshowdescription       = 1;
    $assign->submissiondrafts            = 0;
    $assign->sendnotifications           = 0;
    $assign->sendlatenotifications       = 0;
    $assign->duedate                     = $enddate;
    $assign->allowsubmissionsfromdate    = $startdate;
    $assign->grade                       = 100;
    $assign->timemodified                = time();
    $assign->requiresubmissionstatement  = 0;
    $assign->completionsubmit            = 0;
    $assign->cutoffdate                  = 0;
    $assign->gradingduedate              = 0;
    $assign->teamsubmission              = 0;
    $assign->requireallteammemberssubmit = 0;
    $assign->teamsubmissiongroupingid    = 0;
    $assign->blindmarking                = 0;
    $assign->hidegrader                  = 0;
    $assign->revealidentities            = 0;
    $assign->attemptreopenmethod         = 'none';
    $assign->maxattempts                 = -1;
    $assign->markingworkflow             = 0;
    $assign->markingallocation           = 0;
    $assign->id = $DB->insert_record('assign', $assign);

    // Enable online-text submission.
    $configs = [
        ['plugin' => 'onlinetext', 'subtype' => 'assignsubmission', 'name' => 'enabled',  'value' => '1'],
        ['plugin' => 'file',       'subtype' => 'assignsubmission', 'name' => 'enabled',  'value' => '0'],
        ['plugin' => 'comments',   'subtype' => 'assignfeedback',   'name' => 'enabled',  'value' => '1'],
    ];
    foreach ($configs as $c) {
        $c['assignment'] = $assign->id;
        $DB->insert_record('assign_plugin_config', (object) $c);
    }

    $assign->cmid = dashboard_add_cm($courseid, 'assign', $assign->id, $sectionnum);
    return $assign;
}

function dashboard_add_page($courseid, $name, $sectionnum) {
    global $DB;
    $page = new stdClass();
    $page->course        = $courseid;
    $page->name          = $name;
    $page->intro         = '<p>' . $name . '</p>';
    $page->introformat   = FORMAT_HTML;
    $page->content       = '<h3>' . $name . '</h3><p>Reference material for learning support.</p>';
    $page->contentformat = FORMAT_HTML;
    $page->display       = 5;
    $page->revision      = 1;
    $page->timemodified  = time();
    $page->id = $DB->insert_record('page', $page);
    $page->cmid = dashboard_add_cm($courseid, 'page', $page->id, $sectionnum);
    return $page;
}

function dashboard_add_quiz($courseid, $name, $sectionnum, $startdate, $enddate) {
    global $DB;

    $quiz = new stdClass();
    $quiz->course           = $courseid;
    $quiz->name             = $name;
    $quiz->intro            = '<p>Quiz: ' . $name . '</p>';
    $quiz->introformat      = FORMAT_HTML;
    $quiz->timeopen         = $startdate;
    $quiz->timeclose        = $enddate;
    $quiz->timelimit        = 3600; // 1 hour.
    $quiz->grade            = 100;
    $quiz->sumgrades        = 100;
    $quiz->attempts         = 3;
    $quiz->grademethod      = 1; // Highest grade.
    $quiz->questionsperpage = 0;
    $quiz->shuffleanswers   = 1;
    $quiz->preferredbehaviour = 'deferredfeedback';
    $quiz->timemodified     = time();
    $quiz->timecreated      = time();
    $quiz->id = $DB->insert_record('quiz', $quiz);
    $quiz->cmid = dashboard_add_cm($courseid, 'quiz', $quiz->id, $sectionnum);
    return $quiz;
}

function dashboard_post_discussion($forumid, $courseid, $userid, $subject, $message, $timestamp) {
    global $DB;
    $disc = new stdClass();
    $disc->course        = $courseid;
    $disc->forum         = $forumid;
    $disc->name          = $subject;
    $disc->firstpost     = 0;
    $disc->userid        = $userid;
    $disc->groupid       = -1;
    $disc->assessed      = 0;
    $disc->timemodified  = $timestamp;
    $disc->usermodified  = $userid;
    $disc->timestart     = 0;
    $disc->timeend       = 0;
    $disc->pinned        = 0;
    $disc->id = $DB->insert_record('forum_discussions', $disc);

    $post = new stdClass();
    $post->discussion    = $disc->id;
    $post->parent        = 0;
    $post->userid        = $userid;
    $post->created       = $timestamp;
    $post->modified      = $timestamp;
    $post->mailed        = 1;
    $post->subject       = $subject;
    $post->message       = $message;
    $post->messageformat = FORMAT_HTML;
    $post->messagetrust  = 0;
    $post->attachment    = '';
    $post->totalscore    = 0;
    $post->mailnow       = 0;
    $post->id = $DB->insert_record('forum_posts', $post);

    $DB->set_field('forum_discussions', 'firstpost', $post->id, ['id' => $disc->id]);
    return ['discussion' => $disc, 'post' => $post];
}

function dashboard_post_reply($discussionid, $parentpostid, $userid, $subject, $message, $timestamp) {
    global $DB;
    $post = new stdClass();
    $post->discussion    = $discussionid;
    $post->parent        = $parentpostid;
    $post->userid        = $userid;
    $post->created       = $timestamp;
    $post->modified      = $timestamp;
    $post->mailed        = 1;
    $post->subject       = 'Re: ' . $subject;
    $post->message       = $message;
    $post->messageformat = FORMAT_HTML;
    $post->messagetrust  = 0;
    $post->attachment    = '';
    $post->totalscore    = 0;
    $post->mailnow       = 0;
    $post->id = $DB->insert_record('forum_posts', $post);
    $DB->set_field('forum_discussions', 'timemodified', $timestamp, ['id' => $discussionid]);
    return $post;
}

function dashboard_submit_assignment($assignid, $userid, $text, $timestamp) {
    global $DB;
    $sub = new stdClass();
    $sub->assignment     = $assignid;
    $sub->userid         = $userid;
    $sub->timecreated    = $timestamp;
    $sub->timemodified   = $timestamp;
    $sub->status         = 'submitted';
    $sub->latest         = 1;
    $sub->attemptnumber  = 0;
    $sub->id = $DB->insert_record('assign_submission', $sub);

    $ot = new stdClass();
    $ot->assignment    = $assignid;
    $ot->submission    = $sub->id;
    $ot->onlinetext    = $text;
    $ot->onlineformat  = FORMAT_HTML;
    $DB->insert_record('assignsubmission_onlinetext', $ot);
    return $sub;
}

function dashboard_grade_assignment($assignid, $userid, $gradevalue, $graderid, $timestamp) {
    global $DB;
    $g = new stdClass();
    $g->assignment     = $assignid;
    $g->userid         = $userid;
    $g->timecreated    = $timestamp;
    $g->timemodified   = $timestamp;
    $g->grader         = $graderid;
    $g->grade          = $gradevalue;
    $g->attemptnumber  = 0;
    $DB->insert_record('assign_grades', $g);
}

function random_timestamp($start, $end) {
    return rand(min($start, $end), max($start, $end));
}

/**
 * Insert a logstore_standard_log event.
 */
function dashboard_insert_log($userid, $courseid, $action, $target, $eventname, $timestamp, $extra = []) {
    global $DB, $CFG;

    $log = new stdClass();
    $log->eventname    = $eventname;
    $log->component    = $extra['component'] ?? 'core';
    $log->action       = $action;
    $log->target       = $target;
    $log->objecttable  = $extra['objecttable'] ?? '';
    $log->objectid     = $extra['objectid'] ?? 0;
    $log->crud         = $extra['crud'] ?? 'r';
    $log->edulevel     = $extra['edulevel'] ?? 2; // Participating.
    $log->contextid    = $extra['contextid'] ?? 1;
    $log->contextlevel = $extra['contextlevel'] ?? CONTEXT_SYSTEM;
    $log->contextinstanceid = $extra['contextinstanceid'] ?? 0;
    $log->userid       = $userid;
    $log->courseid     = $courseid;
    $log->relateduserid = $extra['relateduserid'] ?? null;
    $log->anonymous    = 0;
    $log->other        = $extra['other'] ?? 'N;';
    $log->timecreated  = $timestamp;
    $log->origin       = 'web';
    $log->ip           = '127.0.0.1';
    $log->realuserid   = null;

    $DB->insert_record('logstore_standard_log', $log);
}

/**
 * Insert a quiz attempt.
 */
function dashboard_add_quiz_attempt($quizid, $userid, $score, $timestamp) {
    global $DB;

    $attempt = new stdClass();
    $attempt->quiz           = $quizid;
    $attempt->userid         = $userid;
    $attempt->attempt        = 1;
    $attempt->uniqueid       = $DB->get_field_sql("SELECT MAX(uniqueid) FROM {quiz_attempts}") + 1;
    if ($attempt->uniqueid < 1) {
        $attempt->uniqueid = rand(100000, 999999);
    }
    $attempt->layout         = '';
    $attempt->currentpage    = 0;
    $attempt->preview        = 0;
    $attempt->state          = 'finished';
    $attempt->timestart      = $timestamp;
    $attempt->timefinish     = $timestamp + rand(600, 3000);
    $attempt->timemodified   = $attempt->timefinish;
    $attempt->timemodifiedoffline = 0;
    $attempt->timecheckstate = 0;
    $attempt->sumgrades      = $score;
    $attempt->gradednotificationsenttime = null;
    $attempt->id = $DB->insert_record('quiz_attempts', $attempt);

    return $attempt;
}

/**
 * Ensure a grade_items row exists for a course and update grade_grades.
 */
function dashboard_update_course_grade($courseid, $userid, $finalgrade, $grademax = 100) {
    global $DB;

    // Ensure course-level grade_item exists.
    $gradeitem = $DB->get_record('grade_items', [
        'courseid' => $courseid,
        'itemtype' => 'course',
    ]);

    if (!$gradeitem) {
        $gi = new stdClass();
        $gi->courseid     = $courseid;
        $gi->itemtype     = 'course';
        $gi->itemname     = null;
        $gi->grademax     = $grademax;
        $gi->grademin     = 0;
        $gi->timecreated  = time();
        $gi->timemodified = time();
        $gi->sortorder    = 1;
        $gi->id = $DB->insert_record('grade_items', $gi);
        $gradeitem = $DB->get_record('grade_items', ['id' => $gi->id]);
    }

    // Insert grade_grades for this user.
    $existing = $DB->get_record('grade_grades', [
        'itemid' => $gradeitem->id,
        'userid' => $userid,
    ]);
    if (!$existing) {
        $gg = new stdClass();
        $gg->itemid       = $gradeitem->id;
        $gg->userid       = $userid;
        $gg->rawgrade     = $finalgrade;
        $gg->rawgrademax  = $grademax;
        $gg->rawgrademin  = 0;
        $gg->finalgrade   = $finalgrade;
        $gg->hidden       = 0;
        $gg->locked       = 0;
        $gg->timecreated  = time();
        $gg->timemodified = time();
        $DB->insert_record('grade_grades', $gg);
    }
}

// ──────────────────────────────────────────────
// MAIN EXECUTION
// ──────────────────────────────────────────────

cli_heading('Analysis Dashboard — Data Population Script');

// ── Step 1: Create 25 users ──
echo "Creating $NUM_USERS users with Telangana names...\n";
$users = [];
for ($i = 1; $i <= $NUM_USERS; $i++) {
    $uname = 'dashboard_user_' . $i;
    $fname = $FIRST_NAMES[$i - 1];
    $lname = $LAST_NAMES[$i - 1];
    $email = $uname . '@test.moodle.local';
    $pass  = 'Student@' . $passwordSuffix;

    $existing = $DB->get_record('user', ['username' => $uname]);
    if ($existing) {
        // Update.
        $uobj = new stdClass();
        $uobj->id        = $existing->id;
        $uobj->firstname = $fname;
        $uobj->lastname  = $lname;
        $uobj->email     = $email;
        $uobj->password  = hash_internal_user_password($pass);
        $DB->update_record('user', $uobj);
        $users[] = $DB->get_record('user', ['id' => $existing->id]);
        echo 'u';
    } else {
        $u = new stdClass();
        $u->username    = $uname;
        $u->password    = $pass;
        $u->firstname   = $fname;
        $u->lastname    = $lname;
        $u->email       = $email;
        $u->auth        = 'manual';
        $u->confirmed   = 1;
        $u->mnethostid  = $CFG->mnet_localhost_id;
        $u->id = user_create_user($u, true, false);
        $users[] = $u;
        echo '.';
    }
}
echo "\n✓ $NUM_USERS users ready.\n\n";

// ── Step 2: Create categories and role accounts ──
echo "Creating course categories...\n";
$categoryIds = [];
$categoryNames = ['Technology', 'Business', 'Management'];
foreach ($categoryNames as $catname) {
    $existing = $DB->get_record('course_categories', ['name' => $catname, 'parent' => 0]);
    if ($existing) {
        $categoryIds[$catname] = $existing->id;
        echo "  ✓ Category '$catname' already exists (id={$existing->id})\n";
    } else {
        $cat = new stdClass();
        $cat->name      = $catname;
        $cat->parent    = 0;
        $cat->sortorder = 999;
        $cat->visible   = 1;
        $cat->timemodified = time();
        $cat->depth     = 1;
        $cat->path      = '';
        $cat->id = $DB->insert_record('course_categories', $cat);
        $DB->set_field('course_categories', 'path', '/' . $cat->id, ['id' => $cat->id]);
        $categoryIds[$catname] = $cat->id;
        echo "  ✓ Created category '$catname' (id={$cat->id})\n";
    }
}

echo "\nCreating role accounts...\n";
$systemctx = context_system::instance();
$ROLE_ACCOUNTS = [
    ['username' => 'dashboard_manager',   'firstname' => 'Manager',  'lastname' => 'User',    'role' => 'manager',        'password' => 'Manager@' . $passwordSuffix],
    ['username' => 'dashboard_teacher',   'firstname' => 'Teacher',  'lastname' => 'User',    'role' => 'editingteacher', 'password' => 'Teacher@' . $passwordSuffix],
    ['username' => 'dashboard_student',   'firstname' => 'Student',  'lastname' => 'User',    'role' => 'student',        'password' => 'Student@' . $passwordSuffix],
];
$roleUserIds = [];
foreach ($ROLE_ACCOUNTS as $acct) {
    $existing = $DB->get_record('user', ['username' => $acct['username']]);
    if ($existing) {
        $roleUserIds[] = ['id' => $existing->id, 'role' => $acct['role']];
        echo "  ✓ '{$acct['username']}' already exists\n";
        continue;
    }
    $ru = new stdClass();
    $ru->username   = $acct['username'];
    $ru->password   = $acct['password'];
    $ru->firstname  = $acct['firstname'];
    $ru->lastname   = $acct['lastname'];
    $ru->email      = $acct['username'] . '@moodle.local';
    $ru->auth       = 'manual';
    $ru->confirmed  = 1;
    $ru->mnethostid = $CFG->mnet_localhost_id;
    $ru->id = user_create_user($ru, true, false);
    echo "  ✓ Created '{$acct['username']}' (id={$ru->id})\n";
    if (in_array($acct['role'], ['manager'])) {
        $sysrole = $DB->get_record('role', ['shortname' => $acct['role']], '*', MUST_EXIST);
        role_assign($sysrole->id, $ru->id, $systemctx->id);
    }
    $roleUserIds[] = ['id' => $ru->id, 'role' => $acct['role']];
}
echo "\n";

// ── Step 3: Create courses with activities ──
$studentrole     = $DB->get_record('role', ['shortname' => 'student'], '*', MUST_EXIST);
$editteacherrole = $DB->get_record('role', ['shortname' => 'editingteacher'], '*', MUST_EXIST);
$enrolplugin     = enrol_get_plugin('manual');
$adminid         = get_admin()->id;
$summaryLines    = [];

foreach ($COURSE_DEFS as $idx => $def) {
    $duration  = rand(7, 60); // Course has been running for 7-60 days.
    $startdate = time() - ($duration * DAYSECS);
    $enddate   = time() + (30 * DAYSECS);
    $shortname = $def['shortname'] . '_dash_' . time() . '_' . $idx;
    $catid     = $categoryIds[$def['category']] ?? 1;

    echo str_repeat('─', 60) . "\n";
    echo "Course " . ($idx + 1) . "/5: {$def['fullname']}\n";
    echo "  Duration: $duration days | Category: {$def['category']}\n";

    // Create course.
    $coursedata = new stdClass();
    $coursedata->fullname          = $def['fullname'];
    $coursedata->shortname         = $shortname;
    $coursedata->summary           = $def['summary'];
    $coursedata->summaryformat     = FORMAT_HTML;
    $coursedata->format            = 'topics';
    $coursedata->numsections       = 5;
    $coursedata->startdate         = $startdate;
    $coursedata->enddate           = $enddate;
    $coursedata->category          = $catid;
    $coursedata->enablecompletion  = 1;
    $course = create_course($coursedata);
    echo "  ✓ Course created (id={$course->id})\n";

    // Get course context for logs.
    $coursecontext = context_course::instance($course->id);

    // Enrol users.
    $instances = enrol_get_instances($course->id, true);
    $manualinstance = null;
    foreach ($instances as $inst) {
        if ($inst->enrol === 'manual') { $manualinstance = $inst; break; }
    }
    if (!$manualinstance) {
        $eid = $enrolplugin->add_instance($course);
        $manualinstance = $DB->get_record('enrol', ['id' => $eid]);
    }

    // Enrol all 25 users as students.
    foreach ($users as $eu) {
        $enrolplugin->enrol_user($manualinstance, $eu->id, $studentrole->id, $startdate, $enddate);
    }
    // Enrol admin as teacher.
    $enrolplugin->enrol_user($manualinstance, $adminid, $editteacherrole->id);
    // Enrol role accounts.
    foreach ($roleUserIds as $ra) {
        $rarole = $DB->get_record('role', ['shortname' => $ra['role']], '*', MUST_EXIST);
        $enrolplugin->enrol_user($manualinstance, $ra['id'], $rarole->id);
    }
    echo "  ✓ " . count($users) . " students + admin + role accounts enrolled\n";

    // ── Create activities ──
    $section = 1;

    // Forums.
    $forums = [];
    foreach ($def['forums'] as $fname) {
        $forums[] = dashboard_add_forum($course->id, $fname, $section);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($forums) . " forum(s)\n";

    // Assignments.
    $assigns = [];
    foreach ($def['assigns'] as $aname) {
        $assigns[] = dashboard_add_assignment($course->id, $aname, $startdate, $enddate, $section);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($assigns) . " assignment(s)\n";

    // Pages.
    $pages = [];
    foreach ($def['pages'] as $pname) {
        $pages[] = dashboard_add_page($course->id, $pname, $section);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($pages) . " page(s)\n";

    // Quizzes.
    $quizzes = [];
    foreach ($def['quizzes'] as $qname) {
        $quizzes[] = dashboard_add_quiz($course->id, $qname, $section, $startdate, $enddate);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($quizzes) . " quiz(zes)\n";

    // Rebuild course cache.
    rebuild_course_cache($course->id, true);

    // ── Simulate forum activity ──
    $allDiscussions = [];
    $forumActiveUsers = array_slice($users, 0, (int)(count($users) * 0.7));
    foreach ($forumActiveUsers as $fu) {
        $forum = $forums[array_rand($forums)];
        $ts    = random_timestamp($startdate, time());
        $subj  = $DISCUSSION_SUBJECTS[array_rand($DISCUSSION_SUBJECTS)];
        $msg   = $DISCUSSION_MESSAGES[array_rand($DISCUSSION_MESSAGES)];
        $result = dashboard_post_discussion($forum->id, $course->id, $fu->id, $subj, $msg, $ts);
        $allDiscussions[] = $result;
    }
    echo '  ✓ ' . count($allDiscussions) . " forum discussions\n";

    // Replies.
    $replyCount = 0;
    if (!empty($allDiscussions)) {
        $replyUsers = array_slice($users, 0, (int)(count($users) * 0.5));
        foreach ($replyUsers as $ru) {
            $target = $allDiscussions[array_rand($allDiscussions)];
            $ts     = random_timestamp(max($startdate, $target['post']->created), time());
            $rmsg   = $REPLY_MESSAGES[array_rand($REPLY_MESSAGES)];
            dashboard_post_reply($target['discussion']->id, $target['post']->id, $ru->id, $target['discussion']->name, $rmsg, $ts);
            $replyCount++;
        }
    }
    echo "  ✓ $replyCount forum replies\n";

    // ── Simulate assignment submissions & grading ──
    $submissionCount = 0;
    $gradedCount     = 0;
    $assignActiveUsers = array_slice($users, 0, (int)(count($users) * 0.8));
    foreach ($assignActiveUsers as $au) {
        $assign = $assigns[array_rand($assigns)];
        $ts     = random_timestamp($startdate, time());
        $text   = $SUBMISSION_TEXTS[array_rand($SUBMISSION_TEXTS)];
        dashboard_submit_assignment($assign->id, $au->id, $text, $ts);
        $submissionCount++;

        // Grade ~70% of submissions.
        if (rand(1, 100) <= 70) {
            $gradeTs = random_timestamp($ts, time());
            dashboard_grade_assignment($assign->id, $au->id, rand(35, 100), $adminid, $gradeTs);
            $gradedCount++;
        }
    }
    echo "  ✓ $submissionCount submissions ($gradedCount graded)\n";

    // ── Simulate quiz attempts ──
    $quizAttemptCount = 0;
    foreach ($users as $qu) {
        // 75% chance each user attempts a quiz.
        if (rand(1, 100) > 75) {
            continue;
        }
        $quiz = $quizzes[array_rand($quizzes)];
        $ts   = random_timestamp($startdate, time());
        $score = rand(20, 100); // Score out of 100.
        dashboard_add_quiz_attempt($quiz->id, $qu->id, $score, $ts);
        $quizAttemptCount++;
    }
    echo "  ✓ $quizAttemptCount quiz attempts\n";

    // ── Simulate course completions & activity completions ──
    $completionPercent = rand(20, 70);
    $completionCount = max(1, (int)(count($users) * $completionPercent / 100));
    $completedUsers = array_slice($users, 0, $completionCount);
    $allCmIds = $DB->get_records('course_modules', ['course' => $course->id], '', 'id');

    foreach ($completedUsers as $cu) {
        foreach ($allCmIds as $cmrec) {
            $exists = $DB->record_exists('course_modules_completion', [
                'coursemoduleid' => $cmrec->id,
                'userid' => $cu->id,
            ]);
            if (!$exists) {
                $cmc = new stdClass();
                $cmc->coursemoduleid = $cmrec->id;
                $cmc->userid        = $cu->id;
                $cmc->completionstate = 1;
                $cmc->timemodified   = random_timestamp($startdate, time());
                $DB->insert_record('course_modules_completion', $cmc);
            }
        }
        // Course completion record.
        $exists = $DB->record_exists('course_completions', [
            'userid' => $cu->id,
            'course' => $course->id,
        ]);
        if (!$exists) {
            $cc = new stdClass();
            $cc->userid        = $cu->id;
            $cc->course        = $course->id;
            $cc->timeenrolled  = $startdate;
            $cc->timestarted   = $startdate;
            $cc->timecompleted = random_timestamp($startdate, time());
            $DB->insert_record('course_completions', $cc);
        }
    }

    // Partial completions for remaining users (some activities done).
    $partialUsers = array_slice($users, $completionCount);
    foreach ($partialUsers as $pu) {
        $cmArray = array_values($allCmIds);
        $numToComplete = rand(1, max(1, (int)(count($cmArray) * 0.6)));
        shuffle($cmArray);
        for ($ci = 0; $ci < $numToComplete; $ci++) {
            $cmrec = $cmArray[$ci];
            $exists = $DB->record_exists('course_modules_completion', [
                'coursemoduleid' => $cmrec->id,
                'userid' => $pu->id,
            ]);
            if (!$exists) {
                $cmc = new stdClass();
                $cmc->coursemoduleid = $cmrec->id;
                $cmc->userid        = $pu->id;
                $cmc->completionstate = 1;
                $cmc->timemodified   = random_timestamp($startdate, time());
                $DB->insert_record('course_modules_completion', $cmc);
            }
        }
        // Course_completions record with NULL timecompleted (in progress).
        $exists = $DB->record_exists('course_completions', [
            'userid' => $pu->id,
            'course' => $course->id,
        ]);
        if (!$exists) {
            $cc = new stdClass();
            $cc->userid        = $pu->id;
            $cc->course        = $course->id;
            $cc->timeenrolled  = $startdate;
            $cc->timestarted   = random_timestamp($startdate, time());
            $cc->timecompleted = null;
            $DB->insert_record('course_completions', $cc);
        }
    }
    echo "  ✓ $completionCount/$NUM_USERS completed ($completionPercent%), rest partial\n";

    // ── Simulate course grades ──
    foreach ($users as $gu) {
        $grade = rand(25, 100);
        dashboard_update_course_grade($course->id, $gu->id, $grade);
    }
    echo "  ✓ Course grades populated\n";

    // ── Simulate logstore events ──
    // (a) Course view events — needed by site_visits, course_visits, activity_heatmap widgets.
    $logCount = 0;
    for ($day = $duration; $day >= 0; $day--) {
        $dayStart = strtotime("-{$day} days midnight");
        $dayEnd   = $dayStart + DAYSECS - 1;

        // Random subset of users view the course each day.
        $numViewers = rand(3, count($users));
        $shuffledUsers = $users;
        shuffle($shuffledUsers);
        $dailyViewers = array_slice($shuffledUsers, 0, $numViewers);

        foreach ($dailyViewers as $vu) {
            $ts = random_timestamp($dayStart, $dayEnd);
            dashboard_insert_log($vu->id, $course->id, 'viewed', 'course',
                '\\core\\event\\course_viewed', $ts, [
                    'component' => 'core',
                    'contextid' => $coursecontext->id,
                    'contextlevel' => CONTEXT_COURSE,
                    'contextinstanceid' => $course->id,
                ]);
            $logCount++;
        }
    }
    echo "  ✓ $logCount course view log entries\n";

    // (b) Activity events — needed by recent_activity and my_recent_activity widgets.
    $activityLogCount = 0;
    $activityActions = ['viewed', 'submitted', 'graded', 'completed', 'updated', 'created'];
    $activityTargets = ['course_module', 'assign', 'forum', 'quiz', 'page'];

    foreach ($users as $lu) {
        $numEvents = rand(3, 12);
        for ($e = 0; $e < $numEvents; $e++) {
            $ts = random_timestamp($startdate, time());
            $action = $activityActions[array_rand($activityActions)];
            $target = $activityTargets[array_rand($activityTargets)];
            dashboard_insert_log($lu->id, $course->id, $action, $target,
                '\\mod_' . $target . '\\event\\' . $target . '_' . $action, $ts, [
                    'component' => 'mod_' . $target,
                    'contextid' => $coursecontext->id,
                    'contextlevel' => CONTEXT_COURSE,
                    'contextinstanceid' => $course->id,
                    'crud' => ($action === 'viewed') ? 'r' : 'u',
                ]);
            $activityLogCount++;
        }
    }
    echo "  ✓ $activityLogCount activity log entries\n";

    $summaryLines[] = sprintf("  %d. %-40s | %2d days | cat=%s | %d quizzes",
        $idx + 1, $def['fullname'], $duration, $def['category'], count($quizzes));
}

// ── Step 4: Login events — needed by my_login_history and authentication_report widgets ──
echo "\n" . str_repeat('─', 60) . "\n";
echo "Generating login events...\n";
$loginCount = 0;
foreach ($users as $lu) {
    // Simulate logins over the last 30 days.
    for ($day = 30; $day >= 0; $day--) {
        // 60% chance of logging in each day.
        if (rand(1, 100) > 60) {
            continue;
        }
        $dayStart = strtotime("-{$day} days midnight");
        $ts = $dayStart + rand(0, 86399);
        // Login event (for my_login_history — action=loggedin, target=user).
        dashboard_insert_log($lu->id, 0, 'loggedin', 'user',
            '\\core\\event\\user_loggedin', $ts, [
                'component' => 'core',
                'crud' => 'r',
                'edulevel' => 0,
                'other' => serialize(['username' => 'dashboard_user_' . $lu->id]),
            ]);
        $loginCount++;
    }
    // Set lastaccess on user record.
    $DB->set_field('user', 'lastaccess', time() - rand(0, 14 * DAYSECS), ['id' => $lu->id]);
}
echo "✓ $loginCount login events generated\n";

// Some failed login events for authentication_report.
$failedCount = 0;
for ($f = 0; $f < 30; $f++) {
    $ts = time() - rand(0, 30 * DAYSECS);
    $randomUser = $users[array_rand($users)];
    dashboard_insert_log($randomUser->id, 0, 'failed', 'user',
        '\\core\\event\\user_login_failed', $ts, [
            'component' => 'core',
            'crud' => 'r',
            'edulevel' => 0,
        ]);
    $failedCount++;
}
echo "✓ $failedCount failed login events\n";

// ── Final summary ──
echo "\n" . str_repeat('═', 60) . "\n";
echo "✅  ANALYSIS DASHBOARD DATA POPULATION COMPLETE\n";
echo str_repeat('═', 60) . "\n\n";
echo "Courses created:\n";
foreach ($summaryLines as $line) {
    echo $line . "\n";
}
echo "\nUsers: dashboard_user_1 … dashboard_user_$NUM_USERS / Student@$passwordSuffix\n";
echo "Role accounts:\n";
echo "  dashboard_manager  / Manager@$passwordSuffix\n";
echo "  dashboard_teacher  / Teacher@$passwordSuffix\n";
echo "  dashboard_student  / Student@$passwordSuffix\n\n";
echo "Data populated for widgets:\n";
echo "  ✓ Users, courses, categories, enrolments\n";
echo "  ✓ Course completions & activity completions\n";
echo "  ✓ Grade items & grade_grades\n";
echo "  ✓ Quiz attempts\n";
echo "  ✓ Logstore: course views, activity events, logins, failed logins\n";
echo "  ✓ Forum discussions & replies\n";
echo "  ✓ Assignment submissions & grades\n\n";
