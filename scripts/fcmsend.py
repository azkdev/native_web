#!/usr/bin/env python3
"""
Copyright 2019 Luciano Iam <lucianito@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

import sys
import json
from pyfcm import FCMNotification

N = json.loads(open(sys.argv[1],'r').read())

result = FCMNotification(api_key=N['apiKey']).notify_single_device(
	registration_id=N['registrationId'],
	message_title=N['notification']['title'],
	message_body=N['notification']['body'],
	message_icon='ic_notification', # needed for Android
	sound='default', # needed for iOS
	data_message={
		'url': N['notification']['url'],
		'click_action': 'FLUTTER_NOTIFICATION_CLICK' # no not remove
	},
)
 
print(result)
