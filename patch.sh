set -e
mkdir -p www && cp index.html www/
npm init -y >/dev/null
npm i @capacitor/core@6 @capacitor/cli@6 @capacitor/android@6
cat > capacitor.config.json <<'EOF'
{"appId":"com.fahad.uthotehobe","appName":"উঠতেই হবে","webDir":"www"}
EOF
npx cap add android
D=android/app/src/main/java/com/fahad/uthotehobe
mkdir -p $D

cat > $D/AlarmPlugin.java <<'EOF'
package com.fahad.uthotehobe;

import android.app.AlarmManager;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.Calendar;

@CapacitorPlugin(name = "AlarmPlugin")
public class AlarmPlugin extends Plugin {
  static final int NID = 7;
  static final int F = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;

  static PendingIntent fire(Context c) {
    return PendingIntent.getBroadcast(c, 1, new Intent(c, AlarmReceiver.class), F);
  }

  static void schedule(Context c, int h, int m) {
    Calendar cal = Calendar.getInstance();
    cal.set(Calendar.HOUR_OF_DAY, h);
    cal.set(Calendar.MINUTE, m);
    cal.set(Calendar.SECOND, 0);
    cal.set(Calendar.MILLISECOND, 0);
    if (cal.getTimeInMillis() <= System.currentTimeMillis()) cal.add(Calendar.DAY_OF_YEAR, 1);
    AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
    PendingIntent show = PendingIntent.getActivity(c, 2, new Intent(c, MainActivity.class), F);
    am.setAlarmClock(new AlarmManager.AlarmClockInfo(cal.getTimeInMillis(), show), fire(c));
    c.getSharedPreferences("u", 0).edit().putInt("h", h).putInt("m", m).apply();
  }

  @PluginMethod
  public void set(PluginCall call) {
    schedule(getContext(), call.getInt("hour"), call.getInt("minute"));
    call.resolve();
  }

  @PluginMethod
  public void pending(PluginCall call) {
    JSObject o = new JSObject();
    o.put("ring", getContext().getSharedPreferences("u", 0).getBoolean("ring", false));
    call.resolve(o);
  }

  @PluginMethod
  public void clear(PluginCall call) {
    Context c = getContext();
    c.getSharedPreferences("u", 0).edit().putBoolean("ring", false).apply();
    ((NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE)).cancel(NID);
    call.resolve();
  }
}
EOF

cat > $D/AlarmReceiver.java <<'EOF'
package com.fahad.uthotehobe;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.Build;

public class AlarmReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context c, Intent i) {
    SharedPreferences p = c.getSharedPreferences("u", 0);
    p.edit().putBoolean("ring", true).apply();
    AlarmPlugin.schedule(c, p.getInt("h", 5), p.getInt("m", 0));
    NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    if (Build.VERSION.SDK_INT >= 26) {
      AudioAttributes a = new AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_ALARM)
          .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
      NotificationChannel ch = new NotificationChannel("alarm_v1", "Alarm", NotificationManager.IMPORTANCE_HIGH);
      ch.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), a);
      ch.enableVibration(true);
      nm.createNotificationChannel(ch);
    }
    Intent ai = new Intent(c, MainActivity.class);
    ai.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    PendingIntent pi = PendingIntent.getActivity(c, 3, ai, AlarmPlugin.F);
    Notification.Builder b = Build.VERSION.SDK_INT >= 26
        ? new Notification.Builder(c, "alarm_v1") : new Notification.Builder(c);
    b.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
     .setContentTitle("উঠতেই হবে")
     .setContentText("ওঠো! টাস্ক শেষ করো")
     .setCategory(Notification.CATEGORY_ALARM)
     .setPriority(Notification.PRIORITY_MAX)
     .setFullScreenIntent(pi, true)
     .setContentIntent(pi)
     .setOngoing(true);
    Notification n = b.build();
    n.flags |= Notification.FLAG_INSISTENT;
    nm.notify(AlarmPlugin.NID, n);
  }
}
EOF

cat > $D/MainActivity.java <<'EOF'
package com.fahad.uthotehobe;

import android.Manifest;
import android.os.Build;
import android.os.Bundle;
import android.view.WindowManager;
import androidx.core.app.ActivityCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle s) {
    registerPlugin(AlarmPlugin.class);
    super.onCreate(s);
    if (Build.VERSION.SDK_INT >= 27) {
      setShowWhenLocked(true);
      setTurnScreenOn(true);
    }
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    String[] perms = Build.VERSION.SDK_INT >= 33
        ? new String[]{Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.CAMERA}
        : new String[]{Manifest.permission.CAMERA};
    ActivityCompat.requestPermissions(this, perms, 1);
  }
}
EOF

python3 - <<'PY'
p='android/app/src/main/AndroidManifest.xml'
s=open(p,encoding='utf-8').read()
perms='''<uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    '''
s=s.replace('<application',perms+'<application',1)
s=s.replace('</application>','<receiver android:name=".AlarmReceiver" android:exported="false"/>\n    </application>',1)
s=s.replace('android:name=".MainActivity"','android:name=".MainActivity" android:showWhenLocked="true" android:turnScreenOn="true"',1)
open(p,'w',encoding='utf-8').write(s)
PY
npx cap sync android
