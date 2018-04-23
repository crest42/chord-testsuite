#include "../chord/chord.h"
#include "../CHash/chash.h"
#include "example.h"
#include <openssl/sha.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

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
msg_to_string(chord_msg_t msg);
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
    out = stderr;
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
  fprintf(out,
          "%lu: [%d|%d] [%s] %s: ",
          t,
          mynode->id,
          _getpid(),
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
struct fingertable_entry *fingertable = get_fingertable();  
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
    struct node *successorlist = get_successorlist();

struct node *mynode = get_own_node();
  printf("successorlist of %d:\n", mynode->id);

  int myid = -1;
  if (!node_is_null(mynode->successor)) {
    myid = mynode->successor->id;
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
  struct node *mynode = get_own_node();
  struct key** first_key = get_first_key();
  if (*first_key == NULL) {
    printf("no keys yet\n");
    return;
  }
  int i = 0;
  printf("keylist of %d:\n", mynode->id);

  for (struct key* start = *first_key; start != NULL; start = start->next) {
    printf("Key %d: size: %lu id: %d owner: %d next: %p\n",
           i,
           start->size,
           start->id,
           start->owner,
           start->next);
    i++;
  }
  return;
}

void
debug_print_node(struct node* node, bool verbose)
{
  if (!node_is_null(node->predecessor)) {
    printf("%d", node->predecessor->id);
  } else {
    printf("NULL");
  }
  printf("<-%d->", node->id);
  if (node->successor) {
    printf("%d", node->successor->id);
  } else {
    printf("NULL");
  }
  printf("\n");
  if (verbose) {
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
pthread_t mythread1;
pthread_t mythread2;

void
sig_handler(int signo)
{
  if (signo == SIGINT) {
    sigint = true;
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
  if (argc < 1) {
    print_usage();
    return -1;
  }
  char buf[INET6_ADDRSTRLEN];
  char nodeip[INET6_ADDRSTRLEN];
  memset(nodeip, 0, INET6_ADDRSTRLEN);
  char masterip[INET6_ADDRSTRLEN];
  memset(masterip, 0, INET6_ADDRSTRLEN);
  // bool master = false, slave = false;
  struct node* partner = malloc(sizeof(struct node));
  bool silent = false;
  bool interactive = false;
  if (!argv[1] ||
      !(strcmp(argv[1], "master") == 0 || strcmp(argv[1], "slave") == 0) ||
      !argv[2] || !inet_pton(AF_INET6, argv[2], buf)) {
    print_usage();
    return 1;
  }
  if (strcmp(argv[1], "slave") == 0 &&
      (!argv[3] || !inet_pton(AF_INET6, argv[3], buf))) {
    print_usage();
    return 1;
  }
  if (strcmp(argv[1], "slave") == 0) {
    memcpy(nodeip, argv[2], INET6_ADDRSTRLEN - 1);
    memcpy(masterip, argv[3], INET6_ADDRSTRLEN - 1);
    if (argc > 3 && strcmp(argv[4], "silent") == 0) {
      silent = true;
    }
    if (argc > 3 && strcmp(argv[4], "interactive") == 0) {
      interactive = true;
    }
  } else if (strcmp(argv[1], "master") == 0) {
    memcpy(nodeip, argv[2], INET6_ADDRSTRLEN - 1);
    memcpy(masterip, argv[2], INET6_ADDRSTRLEN - 1);
    if (argc > 2 && strcmp(argv[3], "silent") == 0) {
      silent = true;
    }
    if (argc > 2 && strcmp(argv[3], "interactive") == 0) {
      interactive = true;
    }
  }

  FILE* fp;
  struct stat st;
  if (stat("./log", &st) == -1) {
    mkdir("./log", 0700);
  }
  char* fname = malloc(strlen("./log/chord.log") + sizeof(pid_t) + 4);
  sprintf(fname, "./log/chord.%d.log", getpid());
  fp = fopen(fname, "w");
  if (!fp) {
    perror("open state");
    exit(0);
  }

  char* log_fname = malloc(strlen("/tmp/chord_out.log") + 6);
  memset(log_fname, 0, strlen("/tmp/chord_out.log") + 6);
  sprintf(log_fname, "/tmp/chord_out.%d.log", getpid());
#ifdef DEBUG_ENABLE
  FILE* default_out = fopen(log_fname, "w");
  if (!default_out) {
    perror("open stdout log");
    exit(0);
  }
#endif

  if (init_chord(nodeip) == CHORD_ERR) {
    return -1;
  }
  struct node* mynode = get_own_node();
  if (!silent)
    printf("nodekey for %s is: %d\n", nodeip, mynode->id);

  if (strcmp(nodeip, masterip) == 0) {
    if (!silent)
      printf("Create new ring\n");
    add_node(NULL);
  } else {
    if (!silent)
      printf("no master node here connect to %s\n", masterip);
    create_node(masterip, partner);
    add_node(partner);
  }
  init_chash();
  if (!silent)
    printf("create eventloop thread\n");
  pthread_create(&mythread1, NULL, thread_wait_for_msg, (void*)mynode);
  if (!silent)
    printf("create periodic thread\n");
  pthread_create(&mythread2, NULL, thread_periodic, (void*)mynode);

  signal(SIGINT, sig_handler);
  int c = 0;
  char *line = NULL;
  size_t size;
  while (!sigint) {
    if (interactive && getline(&line, &size, stdin) != -1) {
      printf("read %lu bytes real: %lu\n",size,strlen(line));
      if(strncmp(line,"put",3) == 0) {
        char* data = malloc(100);
        memset(data, 0, 100);
        sprintf(data, "%s", line+strlen("put"));
        printf("Insert something into ring\n");
        nodeid_t id;
        put((unsigned char*)data, strlen(data), &id);
        printf("Got %d\n",id);
      }
      if(strncmp(line,"get",3) == 0) {
        nodeid_t id = 0;
        sscanf (line+sizeof("get"),"%d",&id);
        unsigned char buf[MAX_MSG_SIZE];
        memset(buf, 0, sizeof(buf));
        get(id, buf);
        printf("read buf: %s\n", buf);
      }
      if(strcmp(line,"exit\n") == 0) {
        break;
      }
    }
    struct node* node = get_own_node();
    if (!node_is_null(node->predecessor)) {
      if (node->successor) {
        fprintf(fp,
                "%d|%d|%d\n",
                node->predecessor->id,
                node->id,
                node->successor->id);
      } else {
        fprintf(fp, "%d|%d|NULL\n", node->predecessor->id, node->id);
      }
    } else {
      if (node->successor) {
        fprintf(fp, "NULL|%d|%d\n", node->id, node->successor->id);
      } else {
        fprintf(fp, "NULL|%d|NULL\n", node->id);
      }
    }
    fflush(fp);
    sleep(1);
    c++;
  }
  free(partner);
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
