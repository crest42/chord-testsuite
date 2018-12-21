#define _GNU_SOURCE
#include <sys/time.h>
#include <sys/resource.h>
#define CHASH_BACKEND_LINKED
#include "../chord/include/chord.h"
#include "../chord/include/chord.h"
#include "../chord/include/bootstrap.h"
#include "../chord/include/chord_util.h"
#include "../CHash/include/chash_backend.h"
#include "../CHash/include/chash_frontend.h"

#include "example.h"
#include <openssl/sha.h>
#include <pthread.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
pthread_mutex_t mutex;
extern uint32_t key_count;
extern time_t time_start;
extern time_t atm;
extern size_t read_b;
extern size_t write_b;
extern struct childs childs;
extern struct fingertable_entry fingertable[FINGERTABLE_SIZE];
extern struct node successorlist[SUCCESSORLIST_SIZE];
extern struct aggregate stats;
pthread_t mythread1;
pthread_t mythread2;
struct rusage thread_periodic_id;
struct rusage thread_wait_for_msg_id;

extern uint32_t steps_reg;
extern uint32_t steps_reg_find;

extern unsigned long int w_start;
extern unsigned long int w_atm;
extern unsigned long int p_start;
extern unsigned long int p_atm;

static struct chash_backend b = {.get                   = chash_backend_get,
                                 .put                   = chash_backend_put,
                                 .backend_periodic_hook = NULL,
                                 .periodic_data         = NULL};

static struct chash_frontend f = {.get                    = chash_frontend_get,
                                  .put                    = chash_frontend_put,
                                  .put_handler            = handle_put,
                                  .get_handler            = handle_get,
                                  .frontend_periodic_hook = chash_frontend_periodic,
                                  .periodic_data          = NULL,
                                  .sync_handler           = handle_sync,
                                  .sync_fetch_handler     = handle_sync_fetch};

static const char*
log_level_to_string(enum log_level level)
{
  switch (level) {
    case OFF:
      return "OFF";
    case FATAL:
      return "FATAL";
    case ERROR:
      return "ERROR";
    case WARN:
      return "WARN";
    case INFO:
      return "INFO";
    case DEBUG:
      return "DEBUG";
    case ALL:
      return "ALL";
    default:
      return NULL;
  }
}

 char*
msg_to_string(chord_msg_t msg)
{
  switch (msg) {
    case MSG_TYPE_NULL:
      return "MSG_TYPE_NULL";
    case MSG_TYPE_GET_PREDECESSOR:
      return "MSG_TYPE_GET_PREDECESSOR";
    case MSG_TYPE_GET_PREDECESSOR_RESP:
      return "MSG_TYPE_GET_PREDECESSOR_RESP";
    case MSG_TYPE_GET_PREDECESSOR_RESP_NULL:
      return "MSG_TYPE_GET_PREDECESSOR_RESP_NULL";
    case MSG_TYPE_FIND_SUCCESSOR:
      return "MSG_TYPE_FIND_SUCCESSOR";
    case MSG_TYPE_FIND_SUCCESSOR_RESP:
      return "MSG_TYPE_FIND_SUCCESSOR_RESP";
    case MSG_TYPE_FIND_SUCCESSOR_RESP_NEXT:
      return "MSG_TYPE_FIND_SUCCESSOR_RESP_NEXT";
    case MSG_TYPE_GET_SUCCESSOR:
      return "MSG_TYPE_GET_SUCCESSOR";
    case MSG_TYPE_GET_SUCCESSOR_RESP:
      return "MSG_TYPE_GET_SUCCESSOR_RESP";
    case MSG_TYPE_PING:
      return "MSG_TYPE_PING";
    case MSG_TYPE_PONG:
      return "MSG_TYPE_PONG";
    case MSG_TYPE_NO_WAIT:
      return "MSG_TYPE_NO_WAIT";
    case MSG_TYPE_NOTIFY:
      return "MSG_TYPE_NOTIFY";
    case MSG_TYPE_COPY_SUCCESSORLIST:
      return "MSG_TYPE_COPY_SUCCESSORLIST";
    case MSG_TYPE_COPY_SUCCESSORLIST_RESP:
      return "MSG_TYPE_COPY_SUCCESSORLIST_RESP";
    case MSG_TYPE_GET:
      return "MSG_TYPE_GET";
    case MSG_TYPE_GET_RESP:
      return "MSG_TYPE_GET_RESP";
    case MSG_TYPE_PUT:
      return "MSG_TYPE_PUT";
    case MSG_TYPE_PUT_ACK:
      return "MSG_TYPE_PUT_ACK";
    case MSG_TYPE_EXIT:
      return "MSG_TYPE_EXIT";
    case MSG_TYPE_EXIT_ACK:
      return "MSG_TYPE_EXIT_ACK";
    case MSG_TYPE_FIND_SUCCESSOR_LINEAR:
      return "MSG_TYPE_FIND_SUCCESSOR_LINEAR";
    case MSG_TYPE_REFRESH_CHILD:
      return "MSG_TYPE_REFRESH_CHILD";
    case MSG_TYPE_REGISTER_CHILD:
      return "MSG_TYPE_REGISTER_CHILD";
    case MSG_TYPE_REGISTER_CHILD_EFULL:
      return "MSG_TYPE_REGISTER_CHILD_EFULL";
    case MSG_TYPE_REGISTER_CHILD_EWRONG:
      return "MSG_TYPE_REGISTER_CHILD_EWRONG";
    case MSG_TYPE_REGISTER_CHILD_OK:
      return "MSG_TYPE_REGISTER_CHILD_OK";
    case MSG_TYPE_REGISTER_CHILD_REDIRECT:
      return "MSG_TYPE_REGISTER_CHILD_REDIRECT";
    case MSG_TYPE_REFRESH_CHILD_OK:
      return "MSG_TYPE_REFRESH_CHILD_OK";
    case MSG_TYPE_REFRESH_CHILD_REDIRECT:
      return "MSG_TYPE_REFRESH_CHILD_REDIRECT";
    default:
      return "UNKNOWN";
  }
}

void
debug_printf(unsigned long t,
             const char* fname,
             enum log_level level,
             const char* format,
             ...)
{
  struct node *mynode = get_own_node();
  FILE* out = default_out;
  if (level <= ERROR) {
    //out = stderr;
  }

  if ((level & DEBUG_LEVEL) != level) {
    return;
  }
  char max_func_name[DEBUG_MAX_FUNC_NAME];
  memset(max_func_name, 0, DEBUG_MAX_FUNC_NAME);
  strncpy(max_func_name, fname, DEBUG_MAX_FUNC_NAME - 1);
  for (int i = strlen(max_func_name); i < DEBUG_MAX_FUNC_NAME - 1; i++) {
    max_func_name[i] = ' ';
  }
  nodeid_t suc = 0, pre = 0;
  if(get_predecessor()) {
    pre = get_predecessor()->id;
  }
  if(get_successor()) {
    suc = get_successor()->id;
  }
  fprintf(out,
          "%lu: [%d<-%d->%d] [%s] %s: ",
          t,
          pre,
          mynode->id,
          suc,
          log_level_to_string(level),
          max_func_name);
  va_list args;
  va_start(args, format);
  vfprintf(out, format, args);
  va_end(args);
  return;
}

static void
debug_print_fingertable(void)
{
  struct node *mynode = get_own_node();
  printf("fingertable of %d:\n", mynode->id);
  for (int i = 0; i < FINGERTABLE_SIZE; i++) {
    if (!node_is_null(&fingertable[i].node)) {
      printf("%d-%d: node(%d)\n",
             fingertable[i].start,
             (fingertable[i].start + fingertable[i].interval) % CHORD_RING_SIZE,
             fingertable[i].node.id);
    } else {
      printf("%d-%d: node(nil)\n",
             fingertable[i].start,
             (fingertable[i].start + fingertable[i].interval) %
               CHORD_RING_SIZE);
    }
  }
}

static void
debug_print_successorlist(void)
{
  struct node *mynode = get_own_node();
  printf("successorlist of %d:\n", mynode->id);

  int myid = -1;
  if (!node_is_null(get_successor())) {
    myid = get_successor()->id;
  }
  for (int i = 0; i < SUCCESSORLIST_SIZE; i++) {
    if (!node_is_null(&successorlist[i])) {
      printf("successor %d (>%d) is: %d\n", i, myid, successorlist[i].id);
    } else {
      printf("successor %d (>%d) is: null\n", i, myid);
    }
    myid = successorlist[i].id;
  }
}

static void
debug_print_keys(void)
{
  return;
}

void
debug_print_node(struct node* node, bool verbose)
{
  if (!node_is_null(get_predecessor())) {
    printf("%d", get_predecessor()->id);
  } else {
    printf("NULL");
  }
  printf("<-%d->", node->id);
  if (get_successor()) {
    printf("%d", get_successor()->id);
  } else {
    printf("NULL");
  }
  #ifdef CHORD_TREE_ENABLED
  printf("\nchilds:\n");
  for(int i = 0;i<CHORD_TREE_CHILDS;i++) {
    printf("child %d is %d and age %d\n",i,childs.child[i].child,(int)(time(NULL)-childs.child[i].t));
  }
  #endif
  printf("aggregation information: %d nodes, size: %d/%d\n",stats.nodes,stats.used,stats.available);
  if (verbose)
  {
    debug_print_fingertable();
    debug_print_successorlist();
    debug_print_keys();
  }
}

int
hash(unsigned char* out,
     const unsigned char* in,
     size_t in_size,
     size_t out_size)
{
  (void)(out_size);
  SHA1((unsigned char*)in, in_size, out);
  return 0;
}

int sigint = false;

static void getMemory(
    int* currRealMem, int* peakRealMem,
    int* currVirtMem, int* peakVirtMem) {

    // stores each word in status file
    char buffer[1024] = "";

    // linux file contains this-process info
    FILE* file = fopen("/proc/self/status", "r");

    // read the entire file
    while (fscanf(file, " %1023s", buffer) == 1) {

        if (strcmp(buffer, "VmRSS:") == 0) {
            fscanf(file, " %d", currRealMem);
        }
        if (strcmp(buffer, "VmHWM:") == 0) {
            fscanf(file, " %d", peakRealMem);
        }
        if (strcmp(buffer, "VmSize:") == 0) {
            fscanf(file, " %d", currVirtMem);
        }
        if (strcmp(buffer, "VmPeak:") == 0) {
            fscanf(file, " %d", peakVirtMem);
        }
    }
    fclose(file);
}

static void print_node(FILE *fp,bool csv){
    struct node *node = get_own_node();
    time_t t = time(NULL);
    int share = 0;
    if(csv) {
      fprintf(fp,"%d,", (int)t);
    } else {
      fprintf(fp,"time:%d|", (int)t);
    }
    if (!node_is_null(get_predecessor()))
    {
      if(get_predecessor()->id > node->id) {
        share = (CHORD_RING_SIZE - get_predecessor()->id) + node->id;
      }
      else if (get_predecessor()->id == node->id) {
        share = CHORD_RING_SIZE;
      }
      else
      {
        share = node->id - get_predecessor()->id;
      }
      if (get_successor())
      {
        if(csv) {
          fprintf(fp,
                  "%d,%d,%d,",
                  get_predecessor()->id,
                  node->id,
                  get_successor()->id);
        } else {
          fprintf(fp,
                  "pre:%d|me:%d|suc:%d",
                  get_predecessor()->id,
                  node->id,
                  get_successor()->id);
        }
      }
      else
      {
        if(csv) {
          fprintf(fp, "%d,%d,NULL,", get_predecessor()->id, node->id);
        } else {
          fprintf(fp, "pre:%d|me:%d|suc:NULL", get_predecessor()->id, node->id);
        }
      }
    } else {
      if (get_successor()) {
        if(csv) {
          fprintf(fp, "NULL,%d,%d,", node->id, get_successor()->id);
        } else {
          fprintf(fp, "pre:NULL|me:%d|suc:%d", node->id, get_successor()->id);
        }
      } else {
        if(csv) {
          fprintf(fp, "NULL,%d,NULL,", node->id);
        } else {
          fprintf(fp, "pre:NULL|me:%d|suc:NULL", node->id);
        }
      }
    }
    int currRealMem = 0, peakRealMem = 0, currVirtMem = 0, peakVirtMem = 0;
    getMemory(&currRealMem,&peakRealMem,&currVirtMem,&peakVirtMem);
    pthread_mutex_lock (&mutex);
    if(csv) {
      fprintf(fp,"%d,%d,%d,%lu,%lu,%lu,%lu,%lu,%lu,%d,%d,%d,%d,%d,%d,%d\n",
        (int)read_b,
        (int)write_b,
        (int)(atm-time_start),
        thread_wait_for_msg_id.ru_utime.tv_usec,
        thread_wait_for_msg_id.ru_stime.tv_usec,
        thread_periodic_id.ru_utime.tv_usec,
        thread_periodic_id.ru_stime.tv_usec,
        (w_atm-w_start),
        (p_atm-p_start),
        currRealMem,
        peakRealMem,
        currVirtMem,
        peakVirtMem,
        key_count,
        share,
        stats.depth);
    } else {
      fprintf(fp,"|read_b:%d|write_b:%d|duration:%d|wait_cpu_u:%lu|wait_cpu_s:%lu|periodic_cpu_u:%lu|periodic_cpu_s:%lu|periodic_elapsed:%lu|wait_elapsed:%lu|currRealMem:%d|peakRealMem:%d|currVirtMem:%d|peakVirtMem:%d|key_count:%d|share:%d|depth:%d\n",
        (int)read_b,
        (int)write_b,
        (int)(atm-time_start),
        thread_wait_for_msg_id.ru_utime.tv_usec,
        thread_wait_for_msg_id.ru_stime.tv_usec,
        thread_periodic_id.ru_utime.tv_usec,
        thread_periodic_id.ru_stime.tv_usec,
        (w_atm-w_start),
        (p_atm-p_start),
        currRealMem,
        peakRealMem,
        currVirtMem,
        peakVirtMem,
        key_count,
        share,
        stats.depth);
    }
    pthread_mutex_unlock (&mutex);
}

bool insert = false;
void
sig_handler(int signo)
{
  if (signo == SIGINT) {
    sigint = true;
  }
  if (signo == SIGUSR1) {
    insert = true;
  }
}

static void
print_usage(void)
{
  printf(
    "Usage\n\t./example master <bind addr>\n\t./example slave <master addr>\n");
}
int
main(int argc, char* argv[])
{
  printf("start\n");
  if (argc < 1)
  {
    print_usage();
    return -1;
  }
  default_out = stdout;

  char buf[INET6_ADDRSTRLEN];
  char nodeip[INET6_ADDRSTRLEN];
  memset(nodeip, 0, INET6_ADDRSTRLEN);
  char masterip[INET6_ADDRSTRLEN];
  memset(masterip, 0, INET6_ADDRSTRLEN);
  // bool master = false, slave = false;
  struct node* partner = calloc(1,sizeof(struct node));
  bool silent = false;
  if (!argv[1] ||
      !(strcmp(argv[1], "master") == 0 || strcmp(argv[1], "test") == 0 || strcmp(argv[1], "slave") == 0) ||
      !argv[2] || !inet_pton(AF_INET6, argv[2], buf)) {
    print_usage();
    return 1;
  }
  if (strcmp(argv[1], "slave") == 0 &&
      (!argv[3] || !inet_pton(AF_INET6, argv[3], buf))) {
    print_usage();
    return 1;
  }
  bool test = false;
  if (strcmp(argv[1], "slave") == 0) {
    memcpy(nodeip, argv[2], INET6_ADDRSTRLEN - 1);
    memcpy(masterip, argv[3], INET6_ADDRSTRLEN - 1);
  } else if (strcmp(argv[1], "master") == 0) {
    memcpy(nodeip, argv[2], INET6_ADDRSTRLEN - 1);
    memcpy(masterip, argv[2], INET6_ADDRSTRLEN - 1);
  } else if (strcmp(argv[1], "test") == 0) {
    test = true;
    memcpy(nodeip, argv[2], INET6_ADDRSTRLEN - 1);
    memcpy(masterip, argv[3], INET6_ADDRSTRLEN - 1);
  }
  signal(SIGINT, sig_handler);
  signal(SIGUSR1, sig_handler);
  FILE* fp;
  struct stat st;
  if (stat("./log", &st) == -1) {
    mkdir("./log", 0700);
  }

  char* fname = malloc(strlen("./log/chord.log") + sizeof(pid_t) + 4);
  sprintf(fname, "./log/chord.%d.log", getpid());
  fp = fopen(fname, "w");
  free(fname);
  if (!fp) {
    perror("open state");
    exit(0);
  }
  char* log_fname = malloc(strlen("/tmp/chord_out.log") + 7);
  memset(log_fname, 0, strlen("/tmp/chord_out.log") + 7);
  sprintf(log_fname, "/tmp/chord_out.%d.log", getpid());

#ifdef DEBUG_ENABLE
  FILE* default_out = fopen(log_fname, "w");
  if (!default_out) {
    perror("open stdout log");
    exit(0);
  }
#endif
  free(log_fname);
  if (init_chord(nodeip) == CHORD_ERR) {
    return -1;
  }
  struct node* mynode = get_own_node();
  if (!silent)
    printf("nodekey for %s is: %d\n", nodeip, mynode->id);

  if (strcmp(nodeip, masterip) == 0) {
    if (!silent)
      printf("Create new ring\n");
  } else {
    if (!silent)
      printf("no master node here connect to %s\n", masterip);
    add_node_to_bslist_str(masterip);
    printf("master added\n");
  }

  chord_start();
  init_chash(&b,&f);
  pthread_mutex_init (&mutex, NULL);
  if (!silent)
    printf("create eventloop thread\n");
  pthread_create(&mythread1, NULL, thread_wait_for_msg, (void*)&thread_wait_for_msg_id);
  if (!silent)
    printf("create periodic thread\n");
  pthread_create(&mythread2, NULL, thread_periodic, (void*)&thread_periodic_id);

  printf("started\n");
  int c = 0;
    if(test) {
    char *line = NULL;
    size_t size;
    int test_size = 1000;
    unsigned char data[100];
    unsigned char test[100];
    unsigned char h[HASH_DIGEST_SIZE];
    nodeid_t add[test_size];
    int is[test_size];
    while (!sigint)
    {
      if(getline(&line, &size, stdin) != -1) {
         if(strncmp(line,"put",3) == 0) {
           printf("insert %d blocks of data\n",test_size);
           int x = 0;
           for (int i = 0; i < test_size; i++)
           {
             int col = 0;
             memset(data, x, sizeof(data));
             hash(h, (unsigned char *)&x, sizeof(x), HASH_DIGEST_SIZE);
             nodeid_t id = get_mod_of_hash(h, CHORD_RING_SIZE);
             for (int e = 0; e < i; e++)
             {
               if(add[e] == id) {
                 col = 1;
                 break;
               }
             }
             if(col == 1) {
                 x++;
                 i--;
                 continue;
             }
             printf("insert %d id: %d\n",i,id);
             is[i] = x;
             add[i] = id;
             chash_frontend_put(sizeof(int), (unsigned char *)&x, 0, sizeof(data), data);
             x++;
           }
         }
           else if (strncmp(line, "get", 3) == 0)
           {
             printf("fetch %d blocks of data\n",test_size);
             int suc = 0;
             int fail = 0;
             for (int i = 0; i < test_size; i++)
             {
               memset(data, is[i] + 1, sizeof(data));
               memset(test, is[i], sizeof(data));
               chash_frontend_get(sizeof(int), (unsigned char *)&is[i], sizeof(data), data);
               if (memcmp(data, test, sizeof(data)) == 0)
               {
                 printf("%d (%d = %u) true\n", i,is[i],add[i]);
                 suc++;
               }
               else
               {
                 printf("%d (%d = %u) false\n", i,is[i],add[i]);
                 fail++;
               }
             }
             printf("%d/%d successfull %d/%d fail\n", suc, test_size,fail,test_size);
             print_node(fp,true);
           }
      }
    }
  }
  while (!sigint) {
    print_node(fp,true);
    fflush(fp);
    print_node(stdout,false);
    fflush(stdout);
    sleep(1);
    c++;
  }
  free(partner);
fclose(fp);
  printf("wait for eventloop thread\n");
  if (pthread_cancel(mythread1) != 0) {
    printf("Error cancel thread 1\n");
  }
  if (pthread_cancel(mythread2) != 0) {
    printf("Error cancel thread 2s\n");
  }
  fflush(stdout);
  pthread_join(mythread1, NULL);
  pthread_join(mythread2, NULL);
}
