# Thread Monitor Task

Check ALL project channels for threads where Shawn (U0ACHB3MA5Q) or an agent posted and Nexus (U0ACX5EDN1X) hasn't replied.

## Channels to check:
- C0ACL9Q55EX (#quickdraw)
- C0ACSM5LDLJ (#dearnote)
- C0ADM6EG456 (#ghostreel)
- C0AD5K17QP3 (#noyoupick)

## Process:
1. Read last 10 messages from each channel
2. Find messages with reply_count > 0 (threads)
3. Read thread replies using Slack API conversations.replies
4. If Shawn or an agent posted and Nexus hasn't replied → send a DM to the main session alerting about the unanswered thread
5. If all threads are answered → do nothing (silent)

## Important:
- Only alert on threads from last 24 hours
- Only alert if Nexus (U0ACX5EDN1X) is NOT in the reply_users list
- Include the channel name, thread topic, and who's waiting
