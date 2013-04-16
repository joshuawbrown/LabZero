###########################################################################
# Copyright 2012 Joshua Brown
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###########################################################################

package LabZero::RetroHTML;

use strict;
use base qw(Exporter);

our @EXPORT = qw(retro_error_simple retro_error_c64 retro_error_apple2);

sub retro_error_simple {
	my ($error_code, $error_message, $hint) = @_;
	return qq
{<html lang="en">
<head><title>Error $error_code - $error_message</title></head>
<body>
<h1>$error_code $error_message ($hint)</h1>
</body>
</html>};
}

sub retro_error_c64 {

	my ($error_code, $error_message, $hint) = @_;

	return qq
{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html lang="en">
<head>
	<title>Error $error_code - $error_message</title>
	<style>
body {
	font-size: 62.5%; /*this makes fonts 10px */
}
* {
	margin: 0;
	padding: 0;
	border-collapse: collapse;
	border-spacing: 0;
}
img {
	border: 0;
	vertical-align: bottom; 
}
input {
	vertical-align: bottom;
}
.center {
	text-align: center;
}
.cursor {
	width: 14px;
	background: white;
}
body {
	text-align: center;
	background: #9b9bfe;
}
#page {
	text-align: left;
	margin: 50px auto;
	width: 800px;
}
#content {
	background: #3838de;
	padding: 50px;
}
p {
	font-size: 22px;
	padding-bottom: 22px;
	font-family: Courier;
	color: #9b9bfe;
	text-transform: uppercase;
	font-weight: bold;
}
#blinking_cursor {
	background: #9b9bfe;
}
</style>
</head>
<body>
	<div id="page">
		<div id="content">
			<p class="center">**** Commodore 64 Basic V2 ****</p>
			<p class="center">64k Ram system 38911 basic bytes free</p>
			<p>ready.</p>
			<p>load "$hint"</p>
			<p>?SYNTAX ERROR<br>$error_code $error_message</p>
			<p>ready.</p>
			<p><span id="blinking_cursor">&nbsp;</span></p>

		</div>
	</div>

	<script>
	var blinking_cursor = document.getElementById('blinking_cursor');
	setInterval('blink()', 700)
	
	var blinkToggle = 0;
	function blink() {
		if (blinkToggle) {
			blinking_cursor.style.background = blinking_cursor.parentNode.style.color;
			blinkToggle = 0;
		} else {
			console.log('yo');
			blinking_cursor.style.background = 'transparent';
			blinkToggle = 1;
		}
	}	
	</script>
	
</body>

</html>
};

}

sub retro_error_apple2 {

	my ($error_code, $error_message, $hint) = @_;

	return qq
{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html lang="en">
<head>
	<title>Error $error_code - $error_message</title>
<style>
body {
	font-size: 62.5%; /*this makes fonts 10px */
}
* {
	margin: 0;
	padding: 0;
	border-collapse: collapse;
	border-spacing: 0;
}
img {
	border: 0;
	vertical-align: bottom; 
}
input {
	vertical-align: bottom;
}
.center {
	text-align: center;
}
.cursor {
	width: 14px;
	background: white;
}
body {
	text-align: center;
	background: #313131;
}
#page {
	text-align: left;
	margin: 50px auto;
	width: 800px;
}
#content {
	background: #000000;
	padding: 50px;
}

p {
	font-size: 22px;
	padding-bottom: 22px;
	font-family: Courier;
	color: #4bc85d;
	font-weight: bold;
	text-transform: uppercase;
}
#blinking_cursor {
	background: #4bc85d;
}
</style>
</head>
<body>
	<div id="page">
		<div id="content">
			<p class="center">Apple ][</p>
			<p class="center">dos version 3.3&nbsp;&nbsp;system master</p>
			<p class="center">January 1, 1983</p>
			<p>copyright apple computer,inc. 1980,1982</p>
			<p>]run $hint</p>
			<p>File not found<br>$error_code $error_message</p>
			<p>break in 65124</p>
			<p>]<span id="blinking_cursor">&nbsp;</span></p>
		</div>
	</div>
	<script>
	var blinking_cursor = document.getElementById('blinking_cursor');
	setInterval('blink()', 700)
	
	var blinkToggle = 0;
	function blink() {
		if (blinkToggle) {
			blinking_cursor.style.background = blinking_cursor.parentNode.style.color;
			blinkToggle = 0;
		} else {
			console.log('yo');
			blinking_cursor.style.background = 'transparent';
			blinkToggle = 1;
		}
	}	
	</script>
</body>
</html>
};

}

1;
