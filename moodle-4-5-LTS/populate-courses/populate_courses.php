<?php
/**
 * Moodle 4.5 LTS — Course & User Population Script
 *
 * Creates 7 courses with random durations, enrols 20-100 users per course,
 * and simulates activity (forum posts, assignment submissions).
 *
 * Run inside the Moodle container:
 *   php /var/www/html/populate_courses.php
 */

define('CLI_SCRIPT', true);
require(__DIR__ . '/config.php');

global $DB, $CFG, $USER;

// Prevent email errors by setting a valid noreply address and disabling email sending.
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
    echo "Usage: php populate_courses.php [--password-suffix=SUFFIX]\n";
    echo "  --password-suffix, -p   Password suffix for all accounts (default: 123456)\n";
    exit(0);
}
$passwordSuffix = $options['password-suffix'];

// ──────────────────────────────────────────────
// CONFIGURATION
// ──────────────────────────────────────────────

$DURATIONS  = [1, 3, 4, 5, 7, 12];
$MIN_USERS  = 20;
$MAX_USERS  = 100;
$USER_POOL_SIZE = 150;

$FIRST_NAMES = [
    'Ravi', 'Suresh', 'Ramesh', 'Srinivas', 'Venkatesh', 'Harish', 'Naresh', 'Satish', 'Praveen', 'Mahesh',
    'Kavita', 'Sunita', 'Anita', 'Swathi', 'Jyothi', 'Ramya', 'Sravani', 'Mamatha', 'Lavanya', 'Padma',
    'Sai', 'Krishna', 'Arjun', 'Vijay', 'Bhanu', 'Chandu', 'Durga', 'Eswar', 'Ganesh', 'Hanumanth',
    'Indra', 'Jagadeesh', 'Karthik', 'Lakshmi', 'Manasa', 'Nagaraju', 'Omprakash', 'Pradeep', 'Rajesh', 'Shiva',
    'Tirupati', 'Uma', 'Vamshi', 'Anil', 'Kiran', 'Aishwarya', 'Bhavani', 'Charitha', 'Divya', 'Sandeep',
];

$LAST_NAMES = [
    'Reddy', 'Rao', 'Goud', 'Sharma', 'Chary', 'Varma', 'Raju', 'Gupta', 'Singh', 'Kumar',
    'Patel', 'Naidu', 'Chowdary', 'Yadav', 'Mudiraj', 'Kamma', 'Kapu', 'Velama', 'Bommena', 'Katta',
    'Palle', 'Thota', 'Mekala', 'Gujjula', 'Marri', 'Singireddy', 'Vangala', 'Pittala', 'Gajula', 'Boddu',
    'Challa', 'Duggirala', 'Gampa', 'Hanamkonda', 'Irukulla', 'Jolla', 'Kasarla', 'Lakkakula', 'Mitta', 'Nalla',
    'Odnala', 'Pula', 'Racha', 'Salla', 'Tummala', 'Uppala', 'Vavilala', 'Yellamma', 'Zilla', 'Komaravelli',
];

$COURSE_DEFS = [
    [
        'fullname'  => 'Introduction to Programming',
        'shortname' => 'PROG101',
        'summary'   => 'Learn the fundamentals of programming with hands-on exercises.',
        'forums'    => ['Getting Started with Code', 'Code Help & Discussion'],
        'assigns'   => ['Hello World Program', 'Calculator Project'],
        'pages'     => ['Programming Resources'],
    ],
    [
        'fullname'  => 'Digital Marketing Essentials',
        'shortname' => 'DMKT201',
        'summary'   => 'Explore SEO, social media, and online advertising strategies.',
        'forums'    => ['Marketing Strategy Discussion'],
        'assigns'   => ['Social Media Campaign Plan', 'SEO Analysis Report'],
        'pages'     => ['Marketing Tools Guide', 'Case Studies'],
    ],
    [
        'fullname'  => 'Data Analytics Fundamentals',
        'shortname' => 'DATA301',
        'summary'   => 'Master data analysis using modern tools and techniques.',
        'forums'    => ['Data Analysis Q&A', 'Tool Tips & Tricks'],
        'assigns'   => ['Dataset Analysis Project', 'Visualization Dashboard', 'Statistical Report'],
        'pages'     => ['Reference Materials'],
    ],
    [
        'fullname'  => 'Business Communication',
        'shortname' => 'BCOM101',
        'summary'   => 'Develop professional writing, presentation, and negotiation skills.',
        'forums'    => ['Presentation Skills', 'Writing Workshop', 'Networking Tips'],
        'assigns'   => ['Business Email Writing'],
        'pages'     => ['Communication Best Practices'],
    ],
    [
        'fullname'  => 'Web Development Bootcamp',
        'shortname' => 'WEBDEV401',
        'summary'   => 'Build modern websites with HTML, CSS, and JavaScript.',
        'forums'    => ['HTML & CSS Help', 'JavaScript Discussion'],
        'assigns'   => ['Personal Portfolio Website', 'Interactive Web App'],
        'pages'     => ['Web Dev Resources'],
    ],
    [
        'fullname'  => 'Project Management',
        'shortname' => 'PM201',
        'summary'   => 'Learn agile, scrum, and traditional project management methodologies.',
        'forums'    => ['PM Methodologies Discussion'],
        'assigns'   => ['Project Charter Document', 'Risk Management Plan'],
        'pages'     => ['PM Templates Collection', 'Agile vs Waterfall Guide'],
    ],
    [
        'fullname'  => 'Research Methodology',
        'shortname' => 'RSCH501',
        'summary'   => 'Understand qualitative and quantitative research methods.',
        'forums'    => ['Research Design Discussion', 'Literature Review Help'],
        'assigns'   => ['Research Proposal'],
        'pages'     => ['Research Ethics Guide'],
    ],
];

$DISCUSSION_SUBJECTS = [
    'Has anyone tried a different approach to this topic?',
    'I found a great resource I wanted to share',
    'Need help understanding this concept',
    'Tips and tricks for this week\'s material',
    'My experience with the latest assignment',
    'Question about the course expectations',
    'Interesting article related to our studies',
    'Study group — who\'s interested?',
    'Feedback on my draft — please review',
    'Struggling with a concept — any advice?',
];

$DISCUSSION_MESSAGES = [
    '<p>I\'ve been working through the material and wanted to share some thoughts. I think the key takeaway is that practice makes a huge difference. Would love to hear your perspectives.</p>',
    '<p>After spending some time on this, I found that breaking the problem into smaller parts really helps. Has anyone else tried this approach?</p>',
    '<p>I came across an interesting example that relates to our course topic. It really helped me understand the practical applications better.</p>',
    '<p>I\'m finding this week\'s content quite challenging. Can anyone recommend additional resources or study strategies?</p>',
    '<p>Great lecture this week! I especially liked the hands-on component. Here are my notes for anyone who missed it.</p>',
];

$REPLY_MESSAGES = [
    '<p>I completely agree with your point. I had a similar experience and found that consistent practice is key.</p>',
    '<p>Thanks for sharing! This is really helpful. I\'ll definitely try this approach.</p>',
    '<p>Interesting perspective. I would also add that reviewing the fundamentals regularly helps build a stronger foundation.</p>',
    '<p>Could you elaborate a bit more? I\'m curious about the specific steps you followed.</p>',
    '<p>Great insight! I\'ve bookmarked this for future reference. Keep up the excellent work!</p>',
    '<p>I tried something similar and it worked well for me too. The main challenge was getting started.</p>',
    '<p>This is a fantastic resource. I wish I had found it earlier in the course!</p>',
    '<p>Very well explained. I think this will help many students in our class.</p>',
];

$SUBMISSION_TEXTS = [
    '<p>After thorough research and analysis, I have completed this assignment addressing all the key requirements. My approach focused on applying the theoretical concepts we learned in class to practical scenarios. I believe the methodology I used demonstrates a strong understanding of the core principles.</p>',
    '<p>This submission presents my work on the assigned task. I began by reviewing the relevant literature and course materials, then developed my solution step by step. The final result incorporates feedback from peer discussions and reflects careful consideration of best practices.</p>',
    '<p>I am submitting my completed work for this assignment. I took an iterative approach, starting with an outline and progressively refining my work. Key areas of focus included critical thinking, structured analysis, and clear communication of findings.</p>',
    '<p>Please find my submission below. I invested significant time in understanding the problem statement and crafting a comprehensive response. I referenced multiple sources and cross-validated my approach with peers to ensure accuracy.</p>',
    '<p>My submission addresses the assignment objectives as outlined in the brief. I explored various approaches before settling on the methodology presented here, which I believe best demonstrates the skills and knowledge acquired during this course.</p>',
];

$FEEDBACK_QUESTIONS_COURSE = [
    [
        'typ' => 'multichoice',
        'name' => 'Overall Satisfaction',
        'label' => 'q_satisfaction',
        'presentation' => "r>>>>>Very Dissatisfied\n|Dissatisfied\n|Neutral\n|Satisfied\n|Very Satisfied",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Course Content Quality',
        'label' => 'q_content',
        'presentation' => "r>>>>>Poor\n|Below Average\n|Average\n|Good\n|Excellent",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Instructor Effectiveness',
        'label' => 'q_instructor',
        'presentation' => "r>>>>>Poor\n|Below Average\n|Average\n|Good\n|Excellent",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Would You Recommend This Course?',
        'label' => 'q_recommend',
        'presentation' => "r>>>>>Definitely Not\n|Probably Not\n|Maybe\n|Probably Yes\n|Definitely Yes",
    ],
    [
        'typ' => 'textarea',
        'name' => 'Additional Comments',
        'label' => 'q_comments',
        'presentation' => '40|5',
    ],
];

$FEEDBACK_QUESTIONS_OVERALL = [
    [
        'typ' => 'multichoice',
        'name' => 'Overall Program Satisfaction',
        'label' => 'q_program_satisfaction',
        'presentation' => "r>>>>>Very Dissatisfied\n|Dissatisfied\n|Neutral\n|Satisfied\n|Very Satisfied",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Quality of Learning Materials',
        'label' => 'q_materials',
        'presentation' => "r>>>>>Poor\n|Below Average\n|Average\n|Good\n|Excellent",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Support and Guidance Received',
        'label' => 'q_support',
        'presentation' => "r>>>>>Poor\n|Below Average\n|Average\n|Good\n|Excellent",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Relevance to Career Goals',
        'label' => 'q_relevance',
        'presentation' => "r>>>>>Not Relevant\n|Slightly Relevant\n|Moderately Relevant\n|Very Relevant\n|Extremely Relevant",
    ],
    [
        'typ' => 'multichoice',
        'name' => 'Would You Recommend This Program?',
        'label' => 'q_recommend_program',
        'presentation' => "r>>>>>Definitely Not\n|Probably Not\n|Maybe\n|Probably Yes\n|Definitely Yes",
    ],
    [
        'typ' => 'textarea',
        'name' => 'Suggestions for Improvement',
        'label' => 'q_suggestions',
        'presentation' => '40|5',
    ],
];

$FEEDBACK_COMMENTS = [
    'The course was very well structured and easy to follow.',
    'I learned a lot from the practical exercises and assignments.',
    'The instructor was knowledgeable and approachable.',
    'I would appreciate more real-world examples in future sessions.',
    'Overall a great experience. Looking forward to more courses like this.',
    'Some topics could have been covered in more depth.',
    'The pace was just right for my level of understanding.',
    'Excellent learning materials and resources provided.',
    'I found the discussion forums very helpful for clarifying doubts.',
    'More interactive sessions would enhance the learning experience.',
];

// ──────────────────────────────────────────────
// HELPER FUNCTIONS
// ──────────────────────────────────────────────

function populate_add_cm($courseid, $modulename, $instanceid, $sectionnum) {
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

function add_forum($courseid, $name, $sectionnum) {
    global $DB;
    $forum = new stdClass();
    $forum->course       = $courseid;
    $forum->type         = 'general';
    $forum->name         = $name;
    $forum->intro        = '<p>Welcome to the ' . $name . ' forum. Share your ideas and help each other learn.</p>';
    $forum->introformat  = FORMAT_HTML;
    $forum->timemodified = time();
    $forum->id = $DB->insert_record('forum', $forum);
    $forum->cmid = populate_add_cm($courseid, 'forum', $forum->id, $sectionnum);
    return $forum;
}

function add_assignment($courseid, $name, $startdate, $enddate, $sectionnum) {
    global $DB;
    $assign = new stdClass();
    $assign->course                      = $courseid;
    $assign->name                        = $name;
    $assign->intro                       = '<p>Please complete and submit: ' . $name . '</p>';
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

    // Enable online-text submission, disable file submission.
    $configs = [
        ['plugin' => 'onlinetext', 'subtype' => 'assignsubmission', 'name' => 'enabled',  'value' => '1'],
        ['plugin' => 'file',       'subtype' => 'assignsubmission', 'name' => 'enabled',  'value' => '0'],
        ['plugin' => 'comments',   'subtype' => 'assignfeedback',   'name' => 'enabled',  'value' => '1'],
    ];
    foreach ($configs as $c) {
        $c['assignment'] = $assign->id;
        $DB->insert_record('assign_plugin_config', (object) $c);
    }

    $assign->cmid = populate_add_cm($courseid, 'assign', $assign->id, $sectionnum);
    return $assign;
}

function add_page($courseid, $name, $sectionnum) {
    global $DB;
    $page = new stdClass();
    $page->course        = $courseid;
    $page->name          = $name;
    $page->intro         = '<p>' . $name . '</p>';
    $page->introformat   = FORMAT_HTML;
    $page->content       = '<h3>' . $name . '</h3><p>This page contains curated reference material, guides, and links to support your learning journey. Review these resources regularly to reinforce your understanding of the course topics.</p>';
    $page->contentformat = FORMAT_HTML;
    $page->display       = 5;
    $page->revision      = 1;
    $page->timemodified  = time();
    $page->id = $DB->insert_record('page', $page);
    $page->cmid = populate_add_cm($courseid, 'page', $page->id, $sectionnum);
    return $page;
}

function post_discussion($forumid, $courseid, $userid, $subject, $message, $timestamp) {
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

function post_reply($discussionid, $parentpostid, $userid, $subject, $message, $timestamp) {
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

function submit_assignment($assignid, $userid, $text, $timestamp) {
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

function grade_assignment($assignid, $userid, $gradevalue, $graderid, $timestamp) {
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
    return rand($start, $end);
}

function add_feedback($courseid, $name, $intro, $questions, $sectionnum, $anonymous = 1) {
    global $DB;
    $fb = new stdClass();
    $fb->course             = $courseid;
    $fb->name               = $name;
    $fb->intro              = '<p>' . $intro . '</p>';
    $fb->introformat        = FORMAT_HTML;
    $fb->anonymous          = $anonymous;  // 1 = anonymous, 2 = user names shown
    $fb->email_notification = 0;
    $fb->multiple_submit    = 0;
    $fb->autonumbering      = 1;
    $fb->site_after_submit  = '';
    $fb->page_after_submit  = '<p>Thank you for your feedback!</p>';
    $fb->page_after_submitformat = FORMAT_HTML;
    $fb->publish_stats      = 1;
    $fb->timeopen           = 0;
    $fb->timeclose          = 0;
    $fb->timemodified       = time();
    $fb->completionsubmit   = 1;
    $fb->id = $DB->insert_record('feedback', $fb);

    $fb->items = [];
    $position = 1;
    foreach ($questions as $q) {
        $item = new stdClass();
        $item->feedback      = $fb->id;
        $item->template      = 0;
        $item->name          = $q['name'];
        $item->label         = $q['label'];
        $item->typ           = $q['typ'] === 'multichoice' ? 'multichoice' : 'textarea';
        $item->presentation  = $q['presentation'];
        $item->hasvalue      = 1;
        $item->position      = $position;
        $item->required      = ($q['typ'] === 'textarea') ? 0 : 1;
        $item->dependitem    = 0;
        $item->dependvalue   = '';
        $item->options       = '';
        $item->id = $DB->insert_record('feedback_item', $item);
        $fb->items[] = $item;
        $position++;
    }

    $fb->cmid = populate_add_cm($courseid, 'feedback', $fb->id, $sectionnum);
    return $fb;
}

function submit_feedback($feedback, $userid, $timestamp, $commentTexts = []) {
    global $DB;
    $completed = new stdClass();
    $completed->feedback      = $feedback->id;
    $completed->userid        = $userid;
    $completed->timemodified  = $timestamp;
    $completed->random_response = 0;
    $completed->anonymous_response = ($feedback->anonymous == 1) ? 1 : 2;
    $completed->id = $DB->insert_record('feedback_completed', $completed);

    foreach ($feedback->items as $item) {
        $val = new stdClass();
        $val->item       = $item->id;
        $val->completed  = $completed->id;
        $val->course_id  = $feedback->course;

        if ($item->typ === 'multichoice') {
            // Count the options by splitting on the newline-pipe separator.
            $options = explode("\n|", $item->presentation);
            $numOptions = count($options);
            $val->value = (string) rand(1, $numOptions);
        } else {
            // textarea — pick a random comment or leave empty.
            if (!empty($commentTexts)) {
                $val->value = $commentTexts[array_rand($commentTexts)];
            } else {
                $val->value = '';
            }
        }

        $val->tmp_completed = 0;
        $DB->insert_record('feedback_value', $val);
    }
    return $completed;
}

// ──────────────────────────────────────────────
// MAIN EXECUTION
// ──────────────────────────────────────────────

cli_heading('Moodle Course & User Population Script');
echo "Creating user pool of $USER_POOL_SIZE users...\n";

$users = [];
for ($i = 1; $i <= $USER_POOL_SIZE; $i++) {
    $uname = 'testuser_' . $i;
    
    // Generate new details
    $newFirstname = $FIRST_NAMES[array_rand($FIRST_NAMES)];
    $newLastname  = $LAST_NAMES[array_rand($LAST_NAMES)];
    $newEmail     = $uname . '@test.moodle.local';
    $newPassword  = 'Student@' . $passwordSuffix;

    $existing = $DB->get_record('user', ['username' => $uname]);
    if ($existing) {
        // Update existing user
        $updateUser = new stdClass();
        $updateUser->id        = $existing->id;
        $updateUser->firstname = $newFirstname;
        $updateUser->lastname  = $newLastname;
        $updateUser->email     = $newEmail;
        $updateUser->password  = hash_internal_user_password($newPassword);
        
        $DB->update_record('user', $updateUser);
        
        // Reload the full record
        $users[] = $DB->get_record('user', ['id' => $existing->id]);
        echo 'u'; // 'u' for updated
        continue;
    }

    $u = new stdClass();
    $u->username    = $uname;
    $u->password    = $newPassword; // user_create_user handles hashing
    $u->firstname   = $newFirstname;
    $u->lastname    = $newLastname;
    $u->email       = $newEmail;
    $u->auth        = 'manual';
    $u->confirmed   = 1;
    $u->mnethostid  = $CFG->mnet_localhost_id;
    $u->id = user_create_user($u, true, false);
    $users[] = $u;
    echo '.';
}
echo "\n✓ $USER_POOL_SIZE users ready.\n\n";

// Get roles and manual enrol plugin.
$studentrole = $DB->get_record('role', ['shortname' => 'student'], '*', MUST_EXIST);
$enrolplugin = enrol_get_plugin('manual');
$adminid     = get_admin()->id;

// ── Create role accounts ──
echo "Creating role accounts...\n";
$systemctx = context_system::instance();
$ROLE_ACCOUNTS = [
    ['username' => 'manager',           'firstname' => 'Manager',      'lastname' => 'User',    'role' => 'manager',          'password' => 'Manager@' . $passwordSuffix],
    ['username' => 'coursecreator',     'firstname' => 'Course',       'lastname' => 'Creator', 'role' => 'coursecreator',    'password' => 'Coursecreator@' . $passwordSuffix],
    ['username' => 'teacher',           'firstname' => 'Teacher',      'lastname' => 'User',    'role' => 'editingteacher',   'password' => 'Teacher@' . $passwordSuffix],
    ['username' => 'noneditingteacher', 'firstname' => 'Non-editing',  'lastname' => 'Teacher', 'role' => 'teacher',          'password' => 'Noneditingteacher@' . $passwordSuffix],
    ['username' => 'student',           'firstname' => 'Student',      'lastname' => 'User',    'role' => 'student',          'password' => 'Student@' . $passwordSuffix],
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
    // Assign system-level roles.
    if (in_array($acct['role'], ['manager', 'coursecreator'])) {
        $sysrole = $DB->get_record('role', ['shortname' => $acct['role']], '*', MUST_EXIST);
        role_assign($sysrole->id, $ru->id, $systemctx->id);
    }
    $roleUserIds[] = ['id' => $ru->id, 'role' => $acct['role']];
}
echo "\n";

$summaryLines = [];

foreach ($COURSE_DEFS as $idx => $def) {
    $duration    = $DURATIONS[array_rand($DURATIONS)];
    $numUsers    = rand($MIN_USERS, $MAX_USERS);
    $startdate   = time() - ($duration * 86400);
    $enddate     = time() + (30 * 86400);
    $shortname   = $def['shortname'] . '_' . time() . '_' . $idx;

    echo str_repeat('─', 50) . "\n";
    echo "Course " . ($idx + 1) . "/7: {$def['fullname']}\n";
    echo "  Duration: $duration days | Users: $numUsers\n";

    // ── Create course ──
    $coursedata = new stdClass();
    $coursedata->fullname    = $def['fullname'];
    $coursedata->shortname   = $shortname;
    $coursedata->summary     = $def['summary'];
    $coursedata->summaryformat = FORMAT_HTML;
    $coursedata->format      = 'topics';
    $coursedata->numsections = 5;
    $coursedata->startdate   = $startdate;
    $coursedata->enddate     = $enddate;
    $coursedata->category    = 1;
    $coursedata->enablecompletion = 1;
    $course = create_course($coursedata);
    echo "  ✓ Course created (id={$course->id})\n";

    // ── Enrol users ──
    $instances = enrol_get_instances($course->id, true);
    $manualinstance = null;
    foreach ($instances as $inst) {
        if ($inst->enrol === 'manual') { $manualinstance = $inst; break; }
    }
    if (!$manualinstance) {
        $eid = $enrolplugin->add_instance($course);
        $manualinstance = $DB->get_record('enrol', ['id' => $eid]);
    }
    $shuffled = $users;
    shuffle($shuffled);
    $enrolledUsers = array_slice($shuffled, 0, $numUsers);
    foreach ($enrolledUsers as $eu) {
        $enrolplugin->enrol_user($manualinstance, $eu->id, $studentrole->id, $startdate, $enddate);
    }
    // Enrol admin as editing teacher.
    $editteacherrole = $DB->get_record('role', ['shortname' => 'editingteacher'], '*', MUST_EXIST);
    $enrolplugin->enrol_user($manualinstance, $adminid, $editteacherrole->id);
    // Enrol all role accounts with their respective roles.
    foreach ($roleUserIds as $ra) {
        $rarole = $DB->get_record('role', ['shortname' => $ra['role']], '*', MUST_EXIST);
        $enrolplugin->enrol_user($manualinstance, $ra['id'], $rarole->id);
    }
    echo "  ✓ $numUsers students + admin + role accounts enrolled\n";

    // ── Create activities ──
    $forums = [];
    $section = 1;
    foreach ($def['forums'] as $fname) {
        $forums[] = add_forum($course->id, $fname, $section);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($forums) . " forum(s) created\n";

    $assigns = [];
    foreach ($def['assigns'] as $aname) {
        $assigns[] = add_assignment($course->id, $aname, $startdate, $enddate, $section);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($assigns) . " assignment(s) created\n";

    $pages = [];
    foreach ($def['pages'] as $pname) {
        $pages[] = add_page($course->id, $pname, $section);
        $section = min($section + 1, 5);
    }
    echo '  ✓ ' . count($pages) . " page(s) created\n";

    // ── Create course feedback form ──
    $fbName  = 'Course Feedback: ' . $def['fullname'];
    $fbIntro = 'Please share your feedback on the course: ' . $def['fullname'] . '. Your responses help us improve.';
    $courseFeedback = add_feedback($course->id, $fbName, $fbIntro, $FEEDBACK_QUESTIONS_COURSE, $section);
    echo "  ✓ Course feedback form created\n";

    // Simulate ~50% of enrolled students completing the feedback.
    $fbRespondents = array_slice($enrolledUsers, 0, (int)(count($enrolledUsers) * 0.5));
    $fbResponseCount = 0;
    foreach ($fbRespondents as $fbu) {
        $ts = random_timestamp($startdate, $enddate);
        submit_feedback($courseFeedback, $fbu->id, $ts, $FEEDBACK_COMMENTS);
        $fbResponseCount++;
    }
    echo "  ✓ $fbResponseCount feedback responses submitted\n";

    // Rebuild course cache after adding modules.
    rebuild_course_cache($course->id, true);

    // ── Simulate forum activity ──
    $allDiscussions = [];
    $forumActiveUsers = array_slice($enrolledUsers, 0, (int)(count($enrolledUsers) * 0.7));
    foreach ($forumActiveUsers as $fu) {
        $forum = $forums[array_rand($forums)];
        $ts    = random_timestamp($startdate, $enddate);
        $subj  = $DISCUSSION_SUBJECTS[array_rand($DISCUSSION_SUBJECTS)];
        $msg   = $DISCUSSION_MESSAGES[array_rand($DISCUSSION_MESSAGES)];
        $result = post_discussion($forum->id, $course->id, $fu->id, $subj, $msg, $ts);
        $allDiscussions[] = $result;
    }
    echo '  ✓ ' . count($allDiscussions) . " forum discussions created\n";

    // Replies (50% of enrolled users reply to random discussions).
    $replyCount = 0;
    if (!empty($allDiscussions)) {
        $replyUsers = array_slice($enrolledUsers, 0, (int)(count($enrolledUsers) * 0.5));
        foreach ($replyUsers as $ru) {
            $target = $allDiscussions[array_rand($allDiscussions)];
            $ts     = random_timestamp(
                max($startdate, $target['post']->created),
                $enddate
            );
            $rmsg = $REPLY_MESSAGES[array_rand($REPLY_MESSAGES)];
            post_reply(
                $target['discussion']->id,
                $target['post']->id,
                $ru->id,
                $target['discussion']->name,
                $rmsg,
                $ts
            );
            $replyCount++;
        }
    }
    echo "  ✓ $replyCount forum replies created\n";

    // ── Simulate assignment submissions ──
    $submissionCount = 0;
    $gradedCount     = 0;
    $assignActiveUsers = array_slice($enrolledUsers, 0, (int)(count($enrolledUsers) * 0.65));
    foreach ($assignActiveUsers as $au) {
        $assign = $assigns[array_rand($assigns)];
        $ts     = random_timestamp($startdate, $enddate);
        $text   = $SUBMISSION_TEXTS[array_rand($SUBMISSION_TEXTS)];
        submit_assignment($assign->id, $au->id, $text, $ts);
        $submissionCount++;

        // Grade ~60% of submissions.
        if (rand(1, 100) <= 60) {
            $gradeTs = random_timestamp($ts, $enddate);
            grade_assignment($assign->id, $au->id, rand(40, 100), $adminid, $gradeTs);
            $gradedCount++;
        }
    }
    echo "  ✓ $submissionCount assignment submissions ($gradedCount graded)\n";

    // ── Simulate course completion ──
    $completionPercent = rand(10, 60);
    $completionCount = max(1, (int)(count($enrolledUsers) * $completionPercent / 100));
    $completedUsers = array_slice($enrolledUsers, 0, $completionCount);
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
                $cmc->timemodified   = random_timestamp($startdate, $enddate);
                $DB->insert_record('course_modules_completion', $cmc);
            }
        }
        $cc = new stdClass();
        $cc->userid        = $cu->id;
        $cc->course        = $course->id;
        $cc->timeenrolled  = $startdate;
        $cc->timestarted   = $startdate;
        $cc->timecompleted = random_timestamp($startdate, $enddate);
        $DB->insert_record('course_completions', $cc);
    }
    echo "  ✓ $completionCount/$numUsers students completed the course ($completionPercent%)\n";

    $summaryLines[] = sprintf(
        "  %d. %-40s | %2d days | %3d users | %d forums | %d assigns | %d pages | %d feedback responses",
        $idx + 1, $def['fullname'], $duration, $numUsers,
        count($forums), count($assigns), count($pages), $fbResponseCount
    );
}

// ── Create Overall Program Feedback course ──
echo str_repeat('─', 50) . "\n";
echo "Creating Overall Program Feedback course...\n";

$overallCourseData = new stdClass();
$overallCourseData->fullname    = 'Overall Program Feedback';
$overallCourseData->shortname   = 'FEEDBACK_OVERALL_' . time();
$overallCourseData->summary     = 'Share your overall experience and help us improve the program.';
$overallCourseData->summaryformat = FORMAT_HTML;
$overallCourseData->format      = 'topics';
$overallCourseData->numsections = 1;
$overallCourseData->startdate   = time() - (30 * 86400);
$overallCourseData->enddate     = time() + (60 * 86400);
$overallCourseData->category    = 1;
$overallCourseData->enablecompletion = 1;
$overallCourse = create_course($overallCourseData);
echo "  ✓ Overall feedback course created (id={$overallCourse->id})\n";

// Enrol all pool users + role accounts.
$overallInstances = enrol_get_instances($overallCourse->id, true);
$overallManual = null;
foreach ($overallInstances as $inst) {
    if ($inst->enrol === 'manual') { $overallManual = $inst; break; }
}
if (!$overallManual) {
    $eid = $enrolplugin->add_instance($overallCourse);
    $overallManual = $DB->get_record('enrol', ['id' => $eid]);
}
foreach ($users as $u) {
    $enrolplugin->enrol_user($overallManual, $u->id, $studentrole->id);
}
$enrolplugin->enrol_user($overallManual, $adminid, $editteacherrole->id);
foreach ($roleUserIds as $ra) {
    $rarole = $DB->get_record('role', ['shortname' => $ra['role']], '*', MUST_EXIST);
    $enrolplugin->enrol_user($overallManual, $ra['id'], $rarole->id);
}
echo "  ✓ All pool users + role accounts enrolled\n";

// Create the overall feedback activity.
$overallFb = add_feedback(
    $overallCourse->id,
    'Overall Program Feedback',
    'Please share your overall feedback on the entire program. Your input helps us improve all courses.',
    $FEEDBACK_QUESTIONS_OVERALL,
    1
);
echo "  ✓ Overall feedback form created\n";

// Simulate ~40% of all pool users completing the overall feedback.
$overallRespondents = array_slice($users, 0, (int)(count($users) * 0.4));
$overallResponseCount = 0;
foreach ($overallRespondents as $oru) {
    $ts = random_timestamp(time() - (30 * 86400), time());
    submit_feedback($overallFb, $oru->id, $ts, $FEEDBACK_COMMENTS);
    $overallResponseCount++;
}
echo "  ✓ $overallResponseCount overall feedback responses submitted\n";

rebuild_course_cache($overallCourse->id, true);

// ── Final summary ──
echo "\n" . str_repeat('═', 60) . "\n";
echo "✅  POPULATION COMPLETE\n";
echo str_repeat('═', 60) . "\n\n";
echo "Courses created:\n";
foreach ($summaryLines as $line) {
    echo $line . "\n";
}
echo "\nOverall Program Feedback course: {$overallCourse->id} ($overallResponseCount responses)\n\n";
echo "Student pool:  testuser_1 … testuser_$USER_POOL_SIZE  /  Student@$passwordSuffix\n";
echo "Total users in pool: $USER_POOL_SIZE\n\n";
echo "Role accounts (password suffix: $passwordSuffix):\n";
echo "  manager            / Manager@$passwordSuffix\n";
echo "  coursecreator      / Coursecreator@$passwordSuffix\n";
echo "  teacher            / Teacher@$passwordSuffix\n";
echo "  noneditingteacher  / Noneditingteacher@$passwordSuffix\n";
echo "  student            / Student@$passwordSuffix\n\n";
